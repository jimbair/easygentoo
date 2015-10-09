#!/bin/bash
# Script to update a manually compiled Linux kernel in Gentoo.
# Re-written to support multiple arches, as well as Rackspace Cloud.
#
# This script is a bit specific to my needs, but I figured I could
# GPL it for anyone to use and modify to their needs. I try to cover
# anyone building their own kernel manually via make menuconfig.
#
# Note that uname -r doesn't give us linux- in front of the kernel
# version but /usr/src/* does. This causes some formatting/comparison
# issues along the way which I remedy by moving stuff around as I go.
#
# Copyright (C) 2012  James Bair <james.d.bair@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# Specify our $PATH
PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# Variables
arch="$(uname -m)"
if [ -z "${arch}" ]; then
    echo "ERROR: Unable to determine arch. Exiting." >&2
    exit 1
else
    echo "INFO: Architecture is ${arch}"
fi

boot='/boot/'
kernelSymlink='/usr/src/linux'
version='2.01'
newKernel="${kernelSymlink}/arch/${arch}/boot/bzImage"
newConfig="${kernelSymlink}/.config"
grubConf="${boot}grub/grub.conf"

# Specify our script name.
script="$(basename $0 2>/dev/null)"
if [ $? -ne 0 ]; then
    script='kernel-upgrade.sh'
fi

# Find the device or partition a mounted filesystem is tied to.
# Follows the /dev/root symlink.
mountFinder(){
    # Find device assigned to provided mountpoint
    mountpoint=$(mount | egrep "^/dev/.* on $1 type " | awk '{print $1}')
    mountpointNum=$(mount | egrep "^/dev/.* on $1 type " | awk '{print $1}' | wc -l)
    if [ "${mountpointNum}" -gt 1 ]; then
        echo "ERROR: Found more than one mount point - please debug." >&2
    exit 1
    fi

    # Dig in a bit for symlinks if needed.
    if [ "$(ls -l $mountpoint | wc -w)" -eq 11 ]; then
        symcheck=$(ls -l $mountpoint | awk '$10 ~ /\->/ {print $NF}')
        if [ -z "${symcheck}" ]; then
            echo "ERROR: Verifying against a symlink failed - please debug." >&2
            exit 1
        fi

        if [ "${symcheck}" != "${mountpoint:5}" ]; then
            mountpoint="/dev/${symcheck}"
        fi
    fi

    # Note a null response is okay =)
    echo "${mountpoint}"
}

###############################
##### BEGIN SANITY CHECKS #####
###############################

# Must be run as root.
if [ $UID -ne 0 ]; then
    echo "ERROR: $script must be run as root. Exiting." >&2
    exit 1
fi

# This script is designed for Gentoo and will not work on other systems.
if [ ! -d /usr/portage/profiles/ ]; then
    echo 'ERROR: This script is desgined for Gentoo Linux and this is not a Gentoo Linux system.' >&2
    exit 1
fi

# Make sure boot exists, as well as grub
if [ ! -s ${grubConf} ]; then
    echo "ERROR: Grub install not found." >&2
    exit 1
fi

# Used specifically for Rackspace Cloud pv-grub requirements
grep -q ' ro console=hvc0' ${grubConf}
if [ $? -eq 0 ]; then
    kernOpts='ro console=hvc0'
else
    kernOpts=''
fi

# Find our root partition
root="$(mountFinder /)"
if [ -z "$root" ]; then
    echo "ERROR: Unable to find our root mount point. Exiting." >&2
    exit 1
else
    echo "INFO: Found root filesystem partition ${root}"
fi

# Find our boot partition/device that grub needs. Example: hd0,0
# Note $boot is used above, which is why the name differs from $root
# naming convention. Allows for /boot to be on /, but posts a warning.
bootDev="$(mountFinder /boot)"
if [ -z "$bootDev" ]; then
    echo -n "INFO: No boot mount point found - assuming /boot resides on /"
    bootDev="${root}"
    sleep 2
    echo
else
    echo "INFO: Found $boot filesystem partition $bootDev"
fi

# Done to dynamically support both physical partitions like /dev/sda1 as 
# well as Rackspace Cloud servers like /dev/xvda1.
blOffset=$(($(echo ${bootDev} | wc -m) - 3))
bnOffset=$((${blOffset} + 1))

# Find the device letter (a-z)
bootLetter="${bootDev:${blOffset}:1}"

# Find the partition number (0-9)
bootNumber="${bootDev:${bnOffset}}"

# Only supporting 10 chars at this time.
case $bootLetter in
    a)
    grubDev1=0
    ;;

    b)
    grubDev1=1
    ;;

    c)
    grubDev1=2
    ;;

    d)
    grubDev1=3
    ;;

    e)
    grubDev1=4
    ;;

    f)
    grubDev1=5
    ;;

    g)
    grubDev1=6
    ;;

    h)
    grubDev1=7
    ;;

    i)
    grubDev1=8
    ;;

    j)
    grubDev1=9
    ;;

    *)
    echo "Warning: Unsupported configuration. Boot drive letter is not a-j." >&2
    exit 1
    ;;

esac

# Subtract the boot number by 1 (since /dev/sda1 is 0,0; /dev/sda2 would be 0,1 etc)
grubDev2="$((bootNumber-1))"

# Now, patch it all together.
grubRoot="hd${grubDev1},${grubDev2}"

echo "INFO: grub device is $grubRoot"

# Find our current kernel version attached to the $kernelSymlink symlink.
# Make sure it exists
if [ -e $kernelSymlink ]; then
    # Make sure it's a symlink
    if [ -L $kernelSymlink ]; then
        fullKernelPath=$(readlink -e $kernelSymlink 2>&1)
        # Make sure readlink exits cleanly
        if [ $? -ne 0 ]; then
            echo 'ERROR: Unable to find the full path of our Linux kernel. Exiting.' >&2
            exit 1
        else
            echo "SUCCESS: Discovered current Linux kernel source: $fullKernelPath"
        fi
    # If the file exists but isn't a symlink, exit out.
    else
        echo "ERROR: $kernelSymlink is *NOT* a symlink! This is a serious problem. Exiting." >&2
        exit 1
    fi
# If nothing is here, exit out.
else
    echo "ERROR: $kernelSymlink does *NOT* exist on this system! Exiting." >&2
    exit 1
fi

# Now, compare our symlink against our live kernel version. Just a safety check
systemKernelVersion="$(echo linux-$(uname -r))"
sourceKernelVersion="$(echo $fullKernelPath | cut -d / -f 4-4)"
if [ "$systemKernelVersion" != "$sourceKernelVersion" ]; then
    echo "ERROR: The kernel version for $kernelSymlink does not match the current system kernel." >&2
    echo "System Kernel: $systemKernelVersion" >&2
    echo "Source Kernel: $sourceKernelVersion" >&2
    echo "Chances are you've already updated the kernel and have not yet rebooted the system." >&2
    echo "To keep from causing too much confusion, please reboot and try again." >&2
    exit 1
else
    echo "SUCCESS: Both Source & System kernels match: $sourceKernelVersion"
fi

# Move into /usr/src/ since we're going to be working in here.
cd /usr/src/

# Find the latest kernel - Ensure it's not the same as what's configured/running.
latestKernelVersion="$(ls -c | grep -v 'linux$' | grep -v 'rpm' | head -1)"
if [ -z "$latestKernelVersion" ]; then
    echo "ERROR: Unable to find our latest kernel version! Exiting." >&2
    exit 1
else
    echo "SUCCESS: Found latest kernel version: $latestKernelVersion"
fi

# Make sure the latest version is not the same as what we're currently running.
if [ "$sourceKernelVersion" == "$latestKernelVersion" ]; then
    echo "INFO: There are no new kernel versions to install. Exiting."
    exit 0
else
    echo "SUCCESS: Latest kernel version $latestKernelVersion newer than System kernel!"
fi

# Check for .config in our new kernel directory
if [ -s ${latestKernelVersion}/.config ]; then
    echo "INFO: Config file for $latestKernelVersion found!"
    echo "We are going to overwrite this file during the upgrade."
    echo -n "This is expected. Exit now if you wish or press enter to proceed."
    read newKernelConfigPresent
else
    echo "INFO: Config file for $latestKernelVersion not present."
fi

# This is the same as the change to latestKernelVersion later, but we need
# the linux- still and we need to check for this issue earlier in our script.
bootCheck="$(echo $latestKernelVersion | cut -d - -f 2-)"

# Start our checks for stuff in $boot if it does not reside on /
if [ "${root}" != "${bootDev}" ]; then
    # Make sure $boot is mounted. If not, mount it.
    if [ -z "$(mount | grep /boot)" ]; then
        wasBootMounted=no
        echo "INFO: $boot not mounted, mounting."
        mount $boot
        if [ $? -eq 0 ]; then
            echo "SUCCESS: $boot mounted successfully."
        else
            echo "ERROR: Unable to mount $boot! Exiting." >&2
            exit 1
        fi
    else
        wasBootMounted=yes
        echo "INFO: $boot already mounted."
    fi
    # Now that $boot is mounted, check for $grubConf
    if [ -s $grubConf ]; then
        grubConfExist=yes
        echo "INFO: $grubConf found."
    else
        grubConfExist=no
        echo "ERROR: $grubConf is missing!" >&2
        echo "Since $script regenerates this dynamically, this *may* not be a problem." >&2
        echo -n "However, this is unexpected. Exit if needed, otherwise, press enter to continue." >&2
        read grubConfMissing
    fi
else
    # This is a hack - we really should check if we *need* to mount based on
    # if there is a separate /boot and / partition, and if not, no need to worry.
    # However, this is the fastest way without more recoding atm. =)
    wasBootMounted=yes
fi

# Make sure our latest kernel is not in $boot
cd $boot
if [ -n "$(ls | grep $bootCheck)" ]; then
    echo "ERROR: The kernel you are trying to upgrade to is already installed! Exiting." >&2
    exit 1
else
    echo "SUCCESS: Kernel $latestKernelVersion not installed in $boot"
fi

# If we get here, we have passed all checks.
echo "SUCCESS: All clear! We are ready to upgrade your system kernel:

Current: $systemKernelVersion
New: $latestKernelVersion"

################
##### MAIN #####
################

# Go back to /usr/src/
cd /usr/src/

# Time to copy over our old config to the new source directory.
# The check for this can be found above.
cp ${sourceKernelVersion}/.config ${latestKernelVersion}/.config

# Go into the new kernel source directory and upgrade the config
cd $latestKernelVersion

# Print a message to the screen.
echo
echo "*****************************************************************"
echo "****Going to run make oldconfig to migrate our kernel config.****"
echo "***This requires you to give it answers to new kernel options!***"
echo "*****************************************************************"
echo
sleep 5

# Migrate the config to our new kernel
make oldconfig
if [ $? -ne 0 ]; then
    echo "ERROR: make oldconfig errored out unexpectedly. Exiting." >&2
    exit 1
else
    echo "SUCCESS: Upgraded our config file successfully!"
fi

# Now, build our kernel and modules. Shouldn't cause issues if no modules
# are needed.
make
if [ $? -ne 0 ]; then
    echo "ERROR: Building our kernel failed. Exiting." >&2
    exit 1
else
    echo "SUCCESS: Kernel built successfully!"
fi

make modules_install
if [ $? -ne 0 ]; then
    echo "ERROR: Building our kernel modules failed. Exiting." >&2
    exit 1
else
    echo "SUCCESS: Kernel modules built successfully!"
fi

# Go back up a directory
cd /usr/src/

# Time to update our symlink to the new kernel
# This is split into rm/ln since ln -sf does not work on my Gentoo system.
echo -n "Removing old symlink..."
rm -f linux
if [ $? -eq 0 ]; then
    echo 'done.'
else
    echo
    echo "ERROR: Removal of symlink failed. Exiting." >&2
    exit 1
fi
echo -n "Creating new symlink..."
ln -s $latestKernelVersion linux
if [ $? -eq 0 ]; then
    echo 'done.'
else
    echo
    echo "ERROR: Creation of new symlink failed. Exiting." >&2
    exit 1
fi

# Time to copy over our new kernel + setup grub's config
# strip the linux- from our kernel version for grub.
cd $boot
latestKernelVersion="$(echo $latestKernelVersion | cut -d - -f 2-)"

# Copy over our files!
echo -n "INFO: Installing new kernel into ${boot}..."
cp $newKernel kernel-${latestKernelVersion}
if [ $? -eq 0 ]; then
    echo 'done.'
else
    echo
    echo -e "ERROR: Could not copy over kernel image. Exiting." >&2
    exit 1
fi
cp $newConfig config-${latestKernelVersion}
echo -n "INFO: Installing new config into ${boot}..."
if [ $? -eq 0 ]; then
    echo 'done.'
else
    echo
    echo -e "ERROR: Could not copy over kernel config. Exiting." >&2
    exit 1
fi

# Backup our config file if present
if [ "$grubConfExist" == "yes" ]; then
    echo -n "INFO: Backing up ${grubConf}..."
    mv $grubConf ${grubConf}.backup
    if [ $? -eq 0 ]; then
        echo 'done.'
    else
        echo
        echo "ERROR: Backup of $grubConf has failed! Exiting." >&2
        exit 1
    fi
fi

# Create our config file framework
echo -n "INFO: Generating new ${grubConf}..."
touch $grubConf
cat > $grubConf << EOTOP
# grub.conf - Generated dynamically on $(date)
# Upgraded from $sourceKernelVersion to linux-${latestKernelVersion}
# $script v${version}
# Script Author: Jim Bair

default 0
timeout 3
splashimage=($grubRoot)${boot}grub/splash.xpm.gz
EOTOP

# Time to generate our new Kernel config dynamically!
# Make sure we find kernels!
if [ -z "$(ls kernel-*)" ]; then
    echo "ERROR: Unable to find our kernels! Exiting." >&2
    exit 1
fi

for i in $(seq $(ls kernel-* | wc -l)); do
    # Find our kernel (we are already in $boot)
    ourKernel="$(ls -c kernel-* | head -${i} | tail -1)"
    # Find the version (again, same as latestKernelVersion but dynamic for the loop
    ourKernelVersion="$(echo $ourKernel | cut -d - -f 2-)"
    # Verfiy the integrity of what we are generating
    if [ -s "${boot}${ourKernel}" ]; then
        echo "" >> $grubConf
        echo "# $ourKernelVersion" >> $grubConf
        echo "title Gentoo Linux $ourKernelVersion" >> $grubConf
        echo "root ($grubRoot)" >> $grubConf
        echo "kernel ${boot}${ourKernel} root=${root} ${kernOpts}" >> $grubConf
    else
        echo
        echo "ERROR: Tried to generate config entry for ${boot}${ourKernel} which does not exist." >&2
        echo "This is more than likely a bug. Exiting." >&2
        exit 1
    fi
done
echo 'done.'

# All work has been completed. Print summary of helpful info.
echo "SUCCESS: Your system kernel has been upgraded successfully!

Current/Old: $systemKernelVersion
Reboot Into: linux-${latestKernelVersion}
"

echo "Overview of ALL kernel sizes:"
du -h $(ls -c ${boot}kernel-*)

# Get out of $boot
cd /

# If $boot was not originally mounted, unmount it.
if [ "$wasBootMounted" == "no" ]; then
    echo -n "$boot not originally mounted. Unmounting..."
    umount $boot
    echo 'done.'
fi

# All done
exit 0
