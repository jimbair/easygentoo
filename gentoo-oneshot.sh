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
# genkernel with normal sources

# No root, no love
[[ "${UID}" != '0' ]] && exit 1

# No EFI, no love
[[ ! -d '/sys/firmware/efi/' ]] && exit 1

# QEMU image for testing
DISK='/dev/vda'
if [[ ! -b "${DISK}" ]]; then
    echo "ERROR: Our target disk ${DISK} is missing." >&2
    exit 1
fi

# This nested echo is a hack
PARTS=$(ls $(echo $DISK)* | grep -c -v "^${DISK}$")
if [[ "${PARTS}" -ne 0 ]]; then
    echo "ERROR: ${PARTS} partitions found on target disk ${DISK}" >&2
    exit 1
fi

# Let's hit it with the default parts
# TODO: Fix rootfs being a static size; parted pukes if given -1 in script mode
# I have it setup to fit inside a 10GiB disk for all parts (~9GB rootfs)
# If this is too small (5GB) emerge-webrsync pukes
parted --script ${DISK} \
mklabel gpt \
mkpart primary ext4 1MiB 3MiB \
name 1 grub \
mkpart primary ext4 3MiB 131MiB \
name 2 boot \
mkpart primary ext4 131MiB 643MiB \
name 3 swap \
mkpart primary ext4 643MiB 9763MiB \
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

# This should be better, but we're still in the hacking phase
# TODO: Validate the stage3 tarball
baseURL='http://distfiles.gentoo.org/releases/amd64/autobuilds'
latestURL="${baseURL}/latest-stage3-amd64.txt"
latest_stage3=$(curl -s ${latestURL} | tail -n 1 | cut -d ' ' -f 1)
wget "${baseURL}/${latest_stage3}"
if [[ $? -ne 0 ]]; then
    echo "ERROR: Fetching the latest stage3 failed." >&2
    exit 1
fi

tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm -f stage3-*.tar.xz

#
# Here is where you can adjust default configs before we start building things
#
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

# chroot all the things!
# Note - trying || exit 1 does nothing in here sadly
# TODO:
# switch over to git out of the box
# Diddle make.conf a bit
# Make net interface (eth0) dynamic
# Find way to abort if command fails
# Handle config unmasking magically
cat << EOF | chroot /mnt/gentoo
mount ${DISK}2 /boot
emerge-webrsync
emerge --update --deep --newuse @world
emerge --autounmask-write sys-kernel/gentoo-sources sys-kernel/genkernel
etc-update --automode -5
emerge sys-kernel/gentoo-sources sys-kernel/genkernel
genkernel all
echo "${DISK}2   /boot        vfat    noauto,noatime       0 2" > /etc/fstab
echo "${DISK}3   none         swap    sw                   0 0" >> /etc/fstab
echo "${DISK}4   /            ext4    noatime              0 1" >> /etc/fstab
emerge --noreplace net-misc/netifrc
echo 'hostname="gentoo"' > /etc/conf.d/hostname
echo 'config_eth0="dhcp"' > /etc/conf.d/net
ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 default
echo -e 'ChangeMe123\nChangeMe123' | passwd root
emerge app-admin/sysklogd sys-process/cronie
rc-update add sysklogd default
rc-update add cronie default
emerge sys-fs/e2fsprogs sys-fs/dosfstools
emerge net-misc/dhcpcd
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Clean up and run away
cd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
