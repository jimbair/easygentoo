#!/bin/bash
# Script to update a manually compiled Linux kernel in Gentoo.
#
# Currently only supports the x86 arch and grub on Gentoo Linux.
#
# This script is a bit specific to my needs, but I figured I could
# GPL it for anyone to use and modify to their needs. For example,
# I do not build modules. =) I also do not use amd64, PPC or anything
# else. Nor do I use lilo. Modify away!
#
# Note that uname -r doesn't give us linux- in front of the kernel
# version but /usr/src/* does. This causes some formatting/comparison
# issues along the way which I remedy by moving stuff around. This
# can probably be done better, but I just fixed stuff as it came up.
#
# 1.31 - Re-fixed a uname call. Oops!
# 1.3  - Made more stuff dynamic.
# 1.21 - Defined ${boot} properly in the grub config section
# 1.2  - Migrated into github, corrected an echo syntax
# 1.1  - Fixed sort -r bug by using ls -c instead
#      - Added $PATH / $script / $kernelSymlink
#      - Added -d check for /boot/
#      - Added more sanity checking
#        Thanks to David Cantrell for the help on 1.1
#
# 1.0  - Developed and deemed working after some testing.
#
# 0.1  - Development
#
# Copyright (C) 2009  James Bair <james.d.bair@gmail.com>
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
boot='/boot/'
kernelSymlink='/usr/src/linux'
version='1.31'
newKernel="${kernelSymlink}/arch/x86/boot/bzImage"
newConfig="${kernelSymlink}/.config"
grubConf="${boot}grub/grub.conf"
# Specify our script name.
script=$(basename $0 2>&1)
if [ $? -ne 0 ]; then
	script='kernel-upgrade.sh'
fi

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
	echo 'This script is desgined for Gentoo Linux and this is not a Gentoo Linux system.' >&2
	echo 'Exiting.' >&2
	exit 1
fi

# Find our root partition
root="$(mount | egrep '^/dev/[s|h]d[a-z][1-9] on / type ' | awk '{print $1}')"
rootNum="$(mount | egrep '^/dev/[s|h]d[a-z][1-9] on / type ' | awk '{print $1}' | wc -l)"
if [ -z "$root" ]; then
    echo "Unable to find our root mount point. Exiting." >&2
    exit 1
elif [ $rootNum -ne 1 ]; then
    echo "We have $rootNum results and only need 1." >&2
    exit 1
fi

# Find our boot partition/device that grub needs. Example: hd0,0
# The /boot should be using $boot but I really don't want to
# escape this regex =)
bootDev="$(mount | egrep '^/dev/[s|h]d[a-z][1-9] on /boot type ' | awk '{print $1}')"
bootDevNum="$(mount | egrep '^/dev/[s|h]d[a-z][1-9] on /boot type ' | awk '{print $1}' | wc -l)"
if [ -z "$bootDev" ]; then
    echo "Unable to find our boot mount point. Exiting." >&2
    exit 1
elif [ $bootDevNum -ne 1 ]; then
    echo "We have $bootDevNum results and we only need 1." >&2
    exit 1
fi

# Now, find the device letter (a-z)
bootLetter="${bootDev:7:1}"

# Now find the letter (0-9)
bootNumber="${bootDev:8:1}"

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
systemKernelVersion=$(echo linux-$(uname -r))
sourceKernelVersion=$(echo $fullKernelPath | cut -d / -f 4-4)
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
latestKernelVersion=$(ls -c | grep -v 'linux$' | head -1)
if [ -z "$latestKernelVersion" ]; then
	echo "ERROR: Unable to find our latest kernel version! Exiting." >&2
	exit 1
else
	echo "SUCCESS: Found latest kernel version: $latestKernelVersion"
fi

# Make sure the latest version is not the same as what we're currently running.
if [ "$sourceKernelVersion" == "$latestKernelVersion" ]; then
	echo "ERROR: There are no new kernel versions to install! Exiting." >&2
	exit 1
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
bootCheck=$(echo $latestKernelVersion | cut -d - -f 2-)
# Start our checks for stuff in $boot
if [ -d $boot ]; then
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
	echo "ERROR: $boot is missing! This is really bad. Exiting." >&2
	exit 1
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

# Now, build our kernel - Modules disabled by personal preference so
# no need to run make modules_install per Gentoo Handbook.
make
if [ $? -ne 0 ]; then
	echo "ERROR: Building our kernel failed. Exiting." >&2
	exit 1
else
	echo "SUCCESS: Kernel built successfully!"
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
latestKernelVersion=$(echo $latestKernelVersion | cut -d - -f 2-)

# Copy over our files!
echo -n "INFO: Installing new kernel into ${boot}..."
cp $newKernel bzImage-${latestKernelVersion}
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
for i in $(seq $(ls bzImage* | wc -l)); do
	# Find our kernel (we are already in $boot)
	ourKernel=$(ls -c bzImage* | head -${i} | tail -1)
	# Find the version (again, same as latestKernelVersion but dynamic for the loop
	ourKernelVersion=$(echo $ourKernel | cut -d - -f 2-)
	# Verfiy the integrity of what we are generating
	if [ -s "${boot}${ourKernel}" ]; then
		echo "" >> $grubConf
		echo "# $ourKernelVersion" >> $grubConf
		echo "title Gentoo Linux $ourKernelVersion" >> $grubConf
		echo "root ($grubRoot)" >> $grubConf
		echo "kernel ${boot}${ourKernel} root=${root}" >> $grubConf
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
du -h $(ls -c ${boot}bzImage*)

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
