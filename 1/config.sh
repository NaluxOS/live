#!/bin/bash

# This script provides common customization options for the ISO

# The version of Ubuntu to generate.  Successfully tested: bionic, cosmic, disco, eoan, focal, groovy
# See https://wiki.ubuntu.com/DevelopmentCodeNames for details
export TARGET_UBUNTU_VERSION="hirsute"

# The packaged version of the Linux kernel to install on target image.
# See https://wiki.ubuntu.com/Kernel/LTSEnablementStack for details
export TARGET_KERNEL_PACKAGE="linux-generic"

# The file (no extension) of the ISO containing the generated disk image,
# the volume id, and the hostname of the live environment are set from this name.
export TARGET_NAME="nalux"

# The text label shown in GRUB for booting into the live environment
export GRUB_LIVEBOOT_LABEL="Try Nalux without installing"

# The text label shown in GRUB for starting installation
export GRUB_INSTALL_LABEL="Install Nalux"

# Packages for live and installment
export COMMON_PACKAGES=$(awk '{print $0, " "}' packages/install-packages.txt)

# Packages for live only
export LIVE_PACKAGES=$(awk '{print $0, " "}' packages/live-packages.txt)

# Packages to be removed from both live and installment
export REMOVE_PACKAGES=$(awk '{print $0, " "}' packages/remove-packages.txt)
