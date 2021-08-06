#!/bin/bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

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

function setup_chroot() {
    print_h1 "→ RUNNING setup_chroot... [chroot]"

   cat <<EOF > /etc/apt/sources.list
deb http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION main restricted universe multiverse
deb-src http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION main restricted universe multiverse

deb http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-security main restricted universe multiverse
deb-src http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-security main restricted universe multiverse

deb http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-updates main restricted universe multiverse
deb-src http://us.archive.ubuntu.com/ubuntu/ $TARGET_UBUNTU_VERSION-updates main restricted universe multiverse
EOF

    echo "$TARGET_NAME" > /etc/hostname

    print_h2 "• Installing systemd and preparing... [chroot]"
    # we need to install systemd first, to configure machine id
    apt-get update
    apt-get install -y libterm-readline-gnu-perl systemd-sysv

    #configure machine id
    dbus-uuidgen > /etc/machine-id
    ln -fs /etc/machine-id /var/lib/dbus/machine-id

    # don't understand why, but multiple sources indicate this
    dpkg-divert --local --rename --add /sbin/initctl
    ln -s /bin/true /sbin/initctl
}

# Load configuration values from file
function load_config() {
  . "$SCRIPT_DIR/config.sh"
}


function install_pkg() {
    print_h1 "→ RUNNING install_pkg... [chroot]"
    apt-get -y upgrade

    print_h2 "• Installing base live packages... [chroot]"
    # install base live packages
    apt-get install -y \
    sudo \
    ubuntu-standard \
    casper \
    lupin-casper \
    discover \
    laptop-detect \
    os-prober \
    network-manager \
    resolvconf \
    net-tools \
    wireless-tools \
    grub-common \
    grub-gfxpayload-lists \
    grub-pc \
    grub-pc-bin \
    grub2-common \
    locales

    print_h2 "• Installing kernel ($TARGET_KERNEL_PACKAGE)... [chroot]"
    # install kernel
    apt-get install -y --no-install-recommends $TARGET_KERNEL_PACKAGE

    print_h2 "• Installing packages from package folder... [chroot]"
    # Call into config function
    customize_image

    print_h2 "• Cleaning up... [chroot]"
    # remove unused and clean up apt cache
    apt-get autoremove -y


    print_h2 "• Configuring locales and resolvconf... [chroot]}"
    # final touch
    dpkg-reconfigure locales
    dpkg-reconfigure resolvconf

    # network manager
    cat <<EOF > /etc/NetworkManager/NetworkManager.conf
[main]
rc-manager=resolvconf
plugins=ifupdown,keyfile
dns=dnsmasq

[ifupdown]
managed=false
EOF

    dpkg-reconfigure network-manager

    apt-get clean -y
}

function finish_up() {
    print_h1 "→ RUNNING finish_up..."

    # truncate machine id (why??)
    truncate -s 0 /etc/machine-id

    # remove diversion (why??)
    rm /sbin/initctl
    dpkg-divert --rename --remove /sbin/initctl

    rm -rf /tmp/* ~/.bash_history
}

# =============   main  ================

load_config

export HOME=/root
export LC_ALL=C

setup_chroot
install_pkg
finish_up
