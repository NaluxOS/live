#!/bin/bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# =============   main  ================
# Load configuration values from file
. "$SCRIPT_DIR/config.sh"

export HOME=/root
export LC_ALL=C

export DEBIAN_FRONTEND=noninteractive

# we need to install systemd first, to configure machine id
apt-get update
apt-get install -y libterm-readline-gnu-perl systemd-sysv

#configure machine id
dbus-uuidgen > /etc/machine-id
ln -fs /etc/machine-id /var/lib/dbus/machine-id

# don't understand why, but multiple sources indicate this
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl

apt-get -y upgrade

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

# install kernel
apt-get install -y --no-install-recommends $TARGET_KERNEL_PACKAGE

# install common packages
apt-get install -y $COMMON_PACKAGES

# install live only packages
apt-get install -y $LIVE_PACKAGES

# purge
apt-get purge -y $REMOVE_PACKAGES

# remove unused and clean up apt cache
apt-get autoremove -y

# final touch
dpkg-reconfigure locales
dpkg-reconfigure resolvconf

dpkg-reconfigure network-manager

apt-get clean -y

# truncate machine id (why??)
truncate -s 0 /etc/machine-id

# remove diversion (why??)
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl

rm -rf /tmp/* ~/.bash_history