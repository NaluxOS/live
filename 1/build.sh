#!/bin/bash

#set -e                  # exit on error
#set -o pipefail         # exit on pipeline error
#set -u                  # treat unset variable as error
#set -x

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

function parse_options() {
  options=$(getopt -o "s h" -l "skip-setup-host help" -- "$@")

  # Show usage if getopt fails to parse options
  if ! [ $? -eq 0 ]; then
    help
    exit 1
  fi

RUN_SETUP_HOST=true

eval set -- "$options"
  while true; do
    case "$1" in
      -s | --skip-setup-host)
      RUN_SETUP_HOST=false
      ;;

      -h | --help)
      help
      exit 0
      ;;

      --)
      shift
      break
      ;;
    esac
    shift
  done

}

#TODO Make it look nice
function help() {
  cat << EOF
Options:
  -s --skip-setup-host
EOF
}

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
    sudo mount --bind /dev chroot/dev
    sudo mount --bind /run chroot/run
    sudo chroot chroot mount none -t proc /proc
    sudo chroot chroot mount none -t sysfs /sys
    sudo chroot chroot mount none -t devpts /dev/pts
}

function chroot_exit_teardown() {
    sudo chroot chroot umount /proc
    sudo chroot chroot umount /sys
    sudo chroot chroot umount /dev/pts
    sudo umount chroot/dev
    sudo umount chroot/run
}

function check_host() {
    local os_ver
    os_ver=`lsb_release -i | grep -E "(Ubuntu|Debian)"`
    if [[ -z "$os_ver" ]]; then
        echo "WARNING : OS is not Debian or Ubuntu and is untested"
    fi
    if [ $(id -u) -eq 0 ]; then
        echo "This script should not be run as root"
        exit 1
    fi
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
    sudo apt update
    sudo apt install -y binutils debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools
    sudo mkdir -p chroot
}

function debootstrap() {
    print_h1 "→ RUNNING debootstrap..."
    sudo debootstrap  --arch=amd64 --variant=minbase $TARGET_UBUNTU_VERSION chroot http://us.archive.ubuntu.com/ubuntu/
}

function configure_chroot() {
    # network manager
    cat <<EOF > chroot/etc/NetworkManager/NetworkManager.conf
[main]
rc-manager=resolvconf
plugins=ifupdown,keyfile
dns=dnsmasq

[ifupdown]
managed=false
EOF

    cat <<EOF > chroot/etc/apt/sources.list
deb http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION main restricted universe multiverse
deb-src http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION main restricted universe multiverse

deb http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-security main restricted universe multiverse
deb-src http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-security main restricted universe multiverse

deb http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-updates main restricted universe multiverse
deb-src http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-updates main restricted universe multiverse
EOF

    echo "$TARGET_NAME" > chroot/etc/hostname
}

function run_chroot() {
    print_h1 "→ RUNNING run_chroot..."

    print_h2 "• Preparing chroot environment..."
    # we copy the packages folder into chroot so config.sh can still refer to the text files in packages

    sudo cp -r packages chroot/packages

    chroot_enter_setup

    # Setup build scripts in chroot environment
    sudo ln -f $SCRIPT_DIR/chroot_build.sh chroot/root/chroot_build.sh
    if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
        sudo ln -f $SCRIPT_DIR/config.sh chroot/root/config.sh
    fi

    print_h2 "• Launching into chroot..."
    # Launch into chroot environment to build install image.
    sudo chroot chroot /root/chroot_build.sh

    print_h2 "• Left chroot, cleaning up..."
    # Cleanup after image changes
    sudo rm -f chroot/root/chroot_build.sh
    if [[ -f "chroot/root/config.sh" ]]; then
        sudo rm -f chroot/root/config.sh
    fi

    chroot_exit_teardown

   sudo  rm -rf chroot/packages
}

function build_iso() {
    print_h1 "→ RUNNING build_iso..."

    rm -rf image
    mkdir -p image/{casper,isolinux,install}

    # copy kernel files
    sudo cp chroot/boot/vmlinuz-**-**-generic image/casper/vmlinuz
    sudo cp chroot/boot/initrd.img-**-**-generic image/casper/initrd

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
    sudo chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee image/casper/filesystem.manifest
    sudo cp -v image/casper/filesystem.manifest image/casper/filesystem.manifest-desktop
    sudo cp -v packages/remove-packages.txt image/casper/filesystem.manifest-remove
    cat packages/live-packages.txt | while read line
    do
        # clean the line from backslashes and spaces
        echo $line
        sed -i '/$line/d' image/casper/filesystem.manifest-desktop
    done
    print_h2 "• Compressing rootfs..."
    # compress rootfs
    sudo mksquashfs chroot image/casper/filesystem.squashfs \
        -noappend -no-duplicates -no-recovery \
        -wildcards \
        -e "var/cache/apt/archives/*" \
        -e "root/*" \
        -e "root/.*" \
        -e "tmp/*" \
        -e "tmp/.*" \
        -e "swapfile"
    printf $(sudo du -sx --block-size=1 chroot | cut -f1) > image/casper/filesystem.size

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
        sudo mkfs.vfat efiboot.img && \
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

    sudo /bin/bash -c "(find . -type f -print0 | xargs -0 md5sum | grep -v -e 'md5sum.txt' -e 'bios.img' -e 'efiboot.img' > md5sum.txt)"

    sudo xorriso \
        -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$TARGET_NAME" \
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
        -output "$SCRIPT_DIR/$TARGET_NAME.iso" \
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

parse_options "$@"
load_config


if [ $RUN_SETUP_HOST == true ]; then
  setup_host
fi

debootstrap
configure_chroot
run_chroot
build_iso

print_h1 "→ $0 - INITIAL BUILD IS DONE!"
