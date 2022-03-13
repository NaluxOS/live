#!/bin/bash

#set -e                  # exit on error
#set -o pipefail         # exit on pipeline error
#set -u                  # treat unset variable as error
#set -x

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export BUILD_DATE="$(date +%Y%m%d)"

function print_h1() {
  tput setaf 4 && tput bold
  echo "$@"
  tput sgr0
}

function print_h2() {
  tput setaf 6 && tput bold
  echo "$@"
  tput sgr0
}


function chroot_enter_setup() {
    mount --bind /dev chroot/dev
    mount --bind /run chroot/run
    chroot chroot mount none -t proc /proc
    chroot chroot mount none -t sysfs /sys
    chroot chroot mount none -t devpts /dev/pts
}

function chroot_exit_teardown() {
    chroot chroot umount /proc
    chroot chroot umount /sys
    chroot chroot umount /dev/pts
    umount chroot/dev
    umount chroot/run
}

# Load configuration values from file
function load_config() {
    if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
        . "$SCRIPT_DIR/config.sh"
    else
        echo "Unable to find config file  $SCRIPT_DIR/config.sh, aborting."
        exit 1
    fi
}

function setup_host() {
    print_h1 "→ RUNNING setup_host..."
    apt update
    apt install -y xz-utils python3 wget binutils debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools
}

function debootstrap() {
    print_h1 "→ RUNNING debootstrap..."

    #######################################
    # Create default folders and symlinks #
    #######################################

    mkdir chroot
    pushd chroot >/dev/null
        mkdir boot
        mkdir dev
        mkdir etc
        mkdir home
        mkdir media
        mkdir mnt
        mkdir opt
        mkdir proc
        mkdir root
        mkdir run
        mkdir srv
        mkdir sys
        mkdir tmp
        mkdir -p usr/{bin,games,include,lib,lib32,lib64,libx32,local,sbin,share,src}
        mkdir var

        ln -s usr/bin bin
        ln -s usr/lib lib
        ln -s usr/lib32 lib32
        ln -s usr/lib64 lib64
        ln -s usr/libx32 libx32
        ln -s usr/sbin sbin

        # .deb files will be stored here until installed
        mkdir debs
    popd >/dev/null

    # Download and merge Packages files to extract useful information later
    wget -q http://archive.ubuntu.com/ubuntu/dists/$TARGET_UBUNTU_VERSION/main/binary-amd64/Packages.xz -O Packages_main.xz
    xz --decompress Packages_main.xz -c >> Packages
    wget -q http://archive.ubuntu.com/ubuntu/dists/$TARGET_UBUNTU_VERSION/universe/binary-amd64/Packages.xz -O Packages_universe.xz
    xz --decompress Packages_universe.xz -c >> Packages

    for package in $(cat packages/base-packages.txt); do
        # Get the file path on the repo server
        # e.g. pool/main/a/apt/apt_2.2.3_amd64.deb
        repo_filepath=$(python3 parse_packages.py Packages $package Filename)

        if ! [[ "$?" == "0" ]]; then
            echo "Could not parse package Information."
            echo "Package: $package"
        fi

        # Get the hash of the package
        # e.g. 9bd87aaea434a0dca38d5b1bc2c6ced281cb24f0940728f46290ddcc99851434
        sha256=$(python3 parse_packages.py Packages $package SHA256)

        pushd chroot/debs >/dev/null
            echo "Downloading $package"

            wget -q "http://archive.ubuntu.com/ubuntu/$repo_filepath"

            if ! [[ "$?" == "0" ]]; then
                echo "Could not download base package '$package'. Exiting."
                exit 1
            fi


            # ([^/]*)$ means match everything after the last "/"
            filename=$(echo $repo_filepath | grep -o --perl-regex "([^/]*)$")

            if ! [[ "$(sha256sum $filename)" == "$sha256  $filename" ]]; then
                echo "Checksum verification for package '$package' failed."
                echo "Checksum from package was: '$(sha256sum $filename)'"
                echo "Downloaded checksum was: '$sha256  $filename'"
                echo "Exiting."
                exit 1
            fi
        popd >/dev/null
    done

    # Unpack packages into chroot
    # So all the tools are available for installing them later
    pushd chroot >/dev/null
        for deb in $(find debs/*); do
            dpkg-deb --fsys-tarfile $deb | tar -h -xf -
        done 
    popd >/dev/null

    ##############################
    # Create system files        #
    # required by some packages  #
    ##############################

    mknod -m 666 chroot/dev/zero    c 1 5
    mknod -m 666 chroot/dev/full    c 1 7
    mknod -m 666 chroot/dev/random  c 1 8
    mknod -m 666 chroot/dev/urandom c 1 9
    mknod -m 666 chroot/dev/tty     c 5 0
    mknod -m 666 chroot/dev/ptmx    c 5 2
    mknod -m 666 chroot/dev/console c 5 1

    mkdir -p chroot/dev/pts/ chroot/dev/shm/

    ln -sf /proc/self/fd   chroot/dev/fd
    ln -sf /proc/self/fd/0 chroot/dev/stdin
    ln -sf /proc/self/fd/1 chroot/dev/stdout
    ln -sf /proc/self/fd/2 chroot/dev/stderr

    ln -s /usr/bin/mawk chroot/usr/bin/awk

    touch chroot/etc/shells

    # Required by dbus but does not exist in docker
    groupadd messagebus

    # Install all downloaded packages
    for package in $(cat packages/base-packages.txt); do
        repo_filepath=$(python3 parse_packages.py Packages $package Filename)
        filename=$(echo $repo_filepath | grep -o --perl-regex "([^/]*)$")

        print_h1 "$package"
        dpkg -i --root=chroot --force-depends chroot/debs/$filename
        echo ""
    done

    # Cleanup
    rm -rf chroot/debs
    rm Packages
    rm Packages_main.xz
    rm Packages_universe.xz
}

function configure_chroot() {
    rm chroot/etc/resolv.conf

    cat <<EOF > chroot/etc/resolv.conf
nameserver 127.0.0.53
options edns0 trust-ad
search localdomain
EOF

    # Apply apt source entries to the target
    echo "" > chroot/etc/apt/sources.list
    cp -R config/apt/sources.list.d/ chroot/etc/apt/
    cp -R config/apt/apt.conf.d/ chroot/etc/apt/
    # Replace "TARGET_UBUNTU_VERSION" string with actual version
    sed -i "s/TARGET_UBUNTU_VERSION/$TARGET_UBUNTU_VERSION/g" chroot/etc/apt/sources.list.d/*

    # Add keyring entries for every url in config/apt/keyring_urls
    mkdir -p chroot/usr/share/keyrings/
    for key_url in $(cat config/apt/keyring_urls)
    do
        pushd chroot/usr/share/keyrings
        wget -qc $key_url
        popd
    done

    echo "$TARGET_NAME" > chroot/etc/hostname
}

function run_chroot() {
    print_h1 "→ RUNNING run_chroot..."

    print_h2 "• Preparing chroot environment..."
    # we copy the packages folder into chroot so config.sh can still refer to the text files in packages

    cp -r packages chroot/packages

    chroot_enter_setup

    # Setup build scripts in chroot environment
    ln -f $SCRIPT_DIR/chroot_build.sh chroot/root/chroot_build.sh
    if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
        ln -f $SCRIPT_DIR/config.sh chroot/root/config.sh
    fi

    print_h2 "• Launching into chroot..."
    # Launch into chroot environment to build install image.
    chroot chroot /root/chroot_build.sh

    print_h2 "• Left chroot, cleaning up..."
    # Cleanup after image changes
    rm -f chroot/root/chroot_build.sh
    if [[ -f "chroot/root/config.sh" ]]; then
        rm -f chroot/root/config.sh
    fi

    chroot_exit_teardown

    rm -rf chroot/packages
}

function build_iso() {
    print_h1 "→ RUNNING build_iso..."

    rm -rf image
    mkdir -p image/{casper,isolinux,install,pool,dists,.disk}

    # copy kernel files
    cp chroot/boot/vmlinuz-**-**-generic image/casper/vmlinuz
    cp chroot/boot/initrd.img-**-**-generic image/casper/initrd
    
    # Paste disk info using envsubst
    (envsubst < "config/.disk/info") > "image/.disk/info"
    
    # copy pool
    cp -R chroot/pkg/* image/pool
    chown -R $USER:$USER image/pool
    
    # generate dists info
    pushd "image"
    mkdir -p "dists/$TARGET_UBUNTU_VERSION/binary-amd64"
    apt-ftparchive packages "pool" > "dists/$TARGET_UBUNTU_VERSION/binary-amd64/Packages"
    gzip -k "dists/$TARGET_UBUNTU_VERSION/binary-amd64/Packages"
    popd
    
    # remove the package pool from the later to be squashed FS
    rm -rf chroot/pkg

    # grub
    touch image/ubuntu
    cat <<EOF > image/isolinux/grub.cfg

search --set=root --file /ubuntu

insmod all_video

set default="0"
set timeout=30

menuentry "${GRUB_LIVEBOOT_LABEL}" {
   linux /casper/vmlinuz boot=casper nopersistent toram quiet splash ---
   initrd /casper/initrd
}

menuentry "${GRUB_INSTALL_LABEL}" {
   linux /casper/vmlinuz boot=casper only-ubiquity quiet splash ---
   initrd /casper/initrd
}

menuentry "Check disc for defects" {
   linux /casper/vmlinuz boot=casper integrity-check quiet splash ---
   initrd /casper/initrd
}
EOF

    # generate manifest
    chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' | tee image/casper/filesystem.manifest
    cp -v image/casper/filesystem.manifest image/casper/filesystem.manifest-desktop
    cp -v packages/remove-packages.txt image/casper/filesystem.manifest-remove
    cat packages/live-packages.txt | while read line
    do
        # clean the line from backslashes and spaces
        echo $line
        sed -i '/$line/d' image/casper/filesystem.manifest-desktop
    done
    print_h2 "• Compressing rootfs..."
    # compress rootfs
    mksquashfs chroot image/casper/filesystem.squashfs \
        -comp zstd -Xcompression-level 22 \
        -noappend -no-duplicates -no-recovery \
        -wildcards \
        -e "var/cache/apt/archives/*" \
        -e "root/*" \
        -e "root/.*" \
        -e "tmp/*" \
        -e "tmp/.*" \
        -e "swapfile"
    printf $(du -sx --block-size=1 chroot | cut -f1) > image/casper/filesystem.size

    # create diskdefines
    cat <<EOF > image/README.diskdefines
#define DISKNAME  ${GRUB_LIVEBOOT_LABEL}
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  amd64
#define ARCHamd64  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF
    print_h2 "• Creating ISO image..."
    # create iso image
    pushd $SCRIPT_DIR/image
    grub-mkstandalone \
        --format=x86_64-efi \
        --output=isolinux/bootx64.efi \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=isolinux/grub.cfg"

    (
        cd isolinux && \
        dd if=/dev/zero of=efiboot.img bs=1M count=10 && \
        mkfs.vfat efiboot.img && \
        LC_CTYPE=C mmd -i efiboot.img efi efi/boot && \
        LC_CTYPE=C mcopy -i efiboot.img ./bootx64.efi ::efi/boot/
    )

    grub-mkstandalone \
        --format=i386-pc \
        --output=isolinux/core.img \
        --install-modules="linux16 linux normal iso9660 biosdisk memdisk search tar ls" \
        --modules="linux16 linux normal iso9660 biosdisk search" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=isolinux/grub.cfg"

    cat /usr/lib/grub/i386-pc/cdboot.img isolinux/core.img > isolinux/bios.img

    /bin/bash -c "(find . -type f -print0 | xargs -0 md5sum | grep -v -e 'md5sum.txt' -e 'bios.img' -e 'efiboot.img' > md5sum.txt)"

    xorriso \
        -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "${TARGET_NAME_PROPER} ${TARGET_VERSION}" \
        -eltorito-boot boot/grub/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog boot/grub/boot.cat \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
        -e EFI/efiboot.img \
        -no-emul-boot \
        -append_partition 2 0xef isolinux/efiboot.img \
        -output "${SCRIPT_DIR}/out/${TARGET_NAME}_${TARGET_VERSION}_amd64_${BUILD_DATE}.iso" \
        -m "isolinux/efiboot.img" \
        -m "isolinux/bios.img" \
        -graft-points \
           "/EFI/efiboot.img=isolinux/efiboot.img" \
           "/boot/grub/bios.img=isolinux/bios.img" \
           "."

    popd
}

# =============   main  ================

# we always stay in $SCRIPT_DIR
cd $SCRIPT_DIR

export DEBIAN_FRONTEND=noninteractive

load_config

setup_host

debootstrap
configure_chroot
run_chroot
build_iso

print_h1 "→ $0 - INITIAL BUILD IS DONE!"
