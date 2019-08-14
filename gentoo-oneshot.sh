#!/bin/bash
# Simple script for a one-shot install of Gentoo from scratch
# Used to make a fast, bare-bones install at a targeted disk
# Ideally, I'd rather get quickstart working again (or make a new one).

# Liberties taken / assumptions made:
#
# DHCP networking
# No LVM
# EFI-based install
# Default partitions from handbook

# No root, no love
[[ "${UID}" != '0' ]] && exit 1

# QEMU image for testing
DISK='/dev/vda'
if [[ ! -b "${DISK}" ]]; then
    echo "ERROR: Our target disk ${DISK} is missing." >&2
    exit 1
fi

# This nested echo is a hack
PARTS=$(ls $(echo $DISK)* | grep -v "^${DISK}$" | wc -l)
if [[ "${PARTS}" -ne 0 ]]; then
    echo "ERROR: ${PARTS} partitions found on target disk ${DISK}" >&2
    exit 1
fi

# Let's hit it with the default parts
# TODO: Fix rootfs being a static size; parted pukes if given -1 in script mode
# I have it setup to fit inside a 5GiB disk for all parts (~4GB rootfs)
parted --script ${DISK} \
mklabel gpt \
mkpart primary ext4 1MiB 3MiB \
name 1 grub \
mkpart primary ext4 3MiB 131MiB \
name 2 boot \
mkpart primary ext4 131MiB 643MiB \
name 3 swap \
mkpart primary ext4 643MiB 4763MiB \
name 4 rootfs \
set 2 boot on
ec=$?
if [[ "${ec}" -ne 0 ]]; then
    echo "ERROR: parted ran into some sort of issue." >&2
    exit 1
fi

# Format the things
# TODO: Bring in our run() style function
mkfs.fat -F 32 ${DISK}2
mkswap ${DISK}3
swapon ${DISK}3 # needed?
mkfs.ext4 ${DISK}4

# Mount the goods and fetch the gentooz
mount ${DISK}4 /mnt/gentoo
cd /mnt/gentoo
# TODO: Make this dynamic and validated
wget http://distfiles.gentoo.org/releases/amd64/autobuilds/20190811T214502Z/stage3-amd64-20190811T214502Z.tar.xz
tar xpvf stage3-*.tar.bz2 --xattrs-include='*.*' --numeric-owner
#
# Here is where you can adjust default configs before we start building things
#
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
