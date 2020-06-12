#!/bin/bash
# A simple BASH script for a one-shot install of Gentoo at a targeted disk
# Ideally, I'd rather get quickstart/kicktoo working (or make something new)
#
# Liberties taken / assumptions made:
# Installs to either /dev/vda or /dev/sda
# No LVM
# DHCP networking
# EFI-based install
# genkernel used for kernel
# Root partition uses remainder of disk

# root password
ROOTPW='ChangeMe123'

# Find our disk
if [[ -b '/dev/vda' ]]; then
    DISK='/dev/vda'
elif [[ -b '/dev/sda' ]]; then
    DISK='/dev/sda'
else
    echo "ERROR: Unable to locate usable install disk" >&2
    exit 1
fi

# Sizes in MiB and direct from the handbook
# Root filesystem takes up the remainder
GRUBSIZE='2'
BOOTSIZE='128'
SWAPSIZE='512'

# Validations
# Run only as root
[[ "${UID}" != '0' ]] && exit 1

# Must be on EFI
if [[ ! -d '/sys/firmware/efi/' ]]; then
    echo "ERROR: This system is not in EFI Mode. Exiting." >&2
    exit 1
fi

# Must be run on 64-bit
if [[ $(arch) != 'x86_64' ]]; then
    echo "ERROR: This system is not x86_64. Exiting." >&2
    exit 1
fi

# This nested echo is a hack
PARTS=$(ls $(echo $DISK)* | grep -c -v "^${DISK}$")
if [[ "${PARTS}" -ne 0 ]]; then
    echo "ERROR: ${PARTS} partitions found on target disk ${DISK}" >&2
    exit 1
fi

# Make sure the NIC exists
NETDEV=$(route -n | grep '^0.0.0.0' | awk '{print $NF}')
if [[ -z "${NETDEV}" ]]; then
    echo "ERROR: Unable to discover our network device." >&2
    exit 1
fi

ifconfig ${NETDEV} &> /dev/null
if [[ $? -ne 0 ]]; then
    echo "ERROR: Network device ${NETDEV} is missing." >&2
    exit 1
fi

# Turn on SSH in case we need to poke around
if [ -x '/etc/init.d/sshd' ]; then
    /etc/init.d/sshd start
    echo -e "${ROOTPW}\n${ROOTPW}" | passwd root
fi

# There HAS to be a way for parted to support end-of-disk on the final partition
# with the -s flag, but I gave up and started this tragedy. If you use the full
# disk size, parted complains, so we lose <1MiB as a result. It's stupid, but so 
# are computers. I'm sure a flag somewhere I'm overlooking will result in this 
# whole codeblock being purged in the future, as it should be. But it works.
DISKSIZE=$(parted -s ${DISK} unit MiB print 2>/dev/null | grep '^Disk /' | cut -d ' ' -f 3 | cut -d M -f 1)
if [[ -z "${DISKSIZE}" ]]; then
    echo "ERROR: Cannot find the size of the disk ${DISK}" >&2
    exit 1
fi

# Time for some maths
GRUBPART=$((1+${GRUBSIZE}))
BOOTPART=$((${GRUBPART}+${BOOTSIZE}))
SWAPPART=$((${BOOTPART}+${SWAPSIZE}))
ROOTPART=$((${DISKSIZE}-1))

# Let's hit it with the partitions
parted -s -a optimal ${DISK} \
mklabel gpt \
mkpart primary ext4 1MiB ${GRUBPART}MiB \
name 1 grub \
mkpart primary fat32 ${GRUBPART}MiB ${BOOTPART}MiB \
name 2 boot \
mkpart primary linux-swap ${BOOTPART}MiB ${SWAPPART}MiB \
name 3 swap \
mkpart primary ext4 ${SWAPPART}MiB ${ROOTPART}MiB \
name 4 rootfs \
set 2 boot on
if [[ $? -ne 0 ]]; then
    echo "ERROR: parted failed to create our partitions" >&2
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

# Prep the chroot
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

# chroot all the things!
# TODO:
# switch over to git out of the box
# Diddle make.conf a bit
# Find way to abort if any chroot'd command fails
# Handle config unmasking magically
cat << EOF | chroot /mnt/gentoo
echo -e "${ROOTPW}\n${ROOTPW}" | passwd root
echo "${DISK}2   /boot        vfat    noauto,noatime       0 2" > /etc/fstab
echo "${DISK}3   none         swap    sw                   0 0" >> /etc/fstab
echo "${DISK}4   /            ext4    noatime              0 1" >> /etc/fstab
mount /boot
emerge-webrsync
emerge --update --deep --newuse @world
emerge --autounmask-write sys-kernel/gentoo-sources sys-kernel/genkernel
etc-update --automode -5
emerge sys-kernel/gentoo-sources sys-kernel/genkernel
genkernel all --makeopts=-$(grep -c processor /proc/cpuinfo)
emerge --noreplace net-misc/netifrc
echo 'hostname="gentoo"' > /etc/conf.d/hostname
echo "config_${NETDEV}='dhcp'" > /etc/conf.d/net
ln -s /etc/init.d/net.lo /etc/init.d/net.${NETDEV}
rc-update add net.${NETDEV} default
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
emerge app-admin/sysklogd sys-process/cronie sys-fs/e2fsprogs sys-fs/dosfstools net-misc/dhcpcd sys-boot/grub:2
rc-update add sysklogd default
rc-update add cronie default
grub-install --target=x86_64-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Clean up and run away
cd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
