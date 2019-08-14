#!/bin/bash
# GentooUpdate.sh
# Shell script to update Gentoo.
# NOTE: DO NOT REMOVE THE ABOVE LINE! USED FOR SANITY CHECKING! =)
#
# v3.95 - Added basename catch, made our arg handling better.
# v3.94 - Added usage as output instead of 'Input not understood.'
# v3.93 - Added a check for curl when -u is called
# v3.92 - Added a check to ensure script is being run on Gentoo
# v3.91 - Fixed a formatting issue on revdep-rebuild
# v3.9  - Added auto detection/notification of available updates
#       - Made the updater much more intelligent
# v3.8  - Added support to stop when package blocks are found
#       - Misc. formatting changes and small fixes
# v3.72 - Migrated $dl to personal domain
#       - Added GPL License
# v3.71 - A few small fixes
# v3.7  - Fixed some output stuff
# v3.6  - Added automatic makewhatis -u support
#
# All previous versions were pretty bad. Don't worry about them. =)
#
# Copyright (C) 2008  James Bair <james.d.bair@gmail.com>
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

# Must be root to run this script.
if [ $UID -ne 0 ]; then
	echo 'This script must be run as root. Exiting.' >&2
	exit 1
fi

# Must be run on a Gentoo Linux machine only
if [ ! -d /usr/portage/profiles/ ]; then
	echo 'This script is used for updating Gentoo Linux and this is not a Gentoo Linux system.' >&2
	echo 'Exiting.' >&2
	exit 1
fi

# Variables
rev='3.95'
dl='http://www.tsuehpsyde.com/scripts/bash/gentooupdate.sh'
script=$(basename $0 2>/dev/null)
# In case basename is somehow not present.
if [ $? -ne 0 ]; then
	script='gentooupdate.sh'
fi

# Our usage
usage() {
	echo "Usage: $script [option]"
	echo 'If run without an option, it updates the system.'
	echo -e '\nAvailable Options:'
	echo '-v	Prints out the version'
	echo "-u	Updates to the newest version"
}

# Must have 0 or 1 arguments
if [ $# -gt 1 ]; then
	usage >&2
	exit 1
fi

# Exits if given ctrl+c (interrupt) signal.
trap gtfo 2
gtfo() {
        echo 'Caught SIGINT, Exiting.'
        exit 1
}

# Check for updates
checkforupdates() {
	# First, use curl separately to verify exit code.
	newscript=$(curl $dl 2>/dev/null)
	ec=$?
	# Exit code of 6 means unable to resolve
	if [ $ec -eq 6 ]; then
		echo 'ERROR: Unable to resolve the hostname of our updates server!'
		canupdate=0
	# 0 means it connected and got HTML back
	elif [ $ec -eq 0 ]; then
		# Find the latest script's revision
		newrev=$(echo "$newscript" | grep "^rev=" | cut -d \' -f 2-2)
		# Check for null. This could be lots of things.
		if [ -z "$newrev" ]; then
			echo "WARNING: Either our updates site is down, the URL changed, or our revision checks have become obsolete." >&2
			canupdate=0
		# If we have a revision, let's check if it's newer =) Use string compares since bash is picky about numbers.
		else
			if [ "$rev" != "$newrev" ]; then
				echo "A new version of $script is available!"
				echo "Current version: $rev"
				echo "New Version: $newrev"
				canupdate=1
			else
				echo "$script is already up to date. Exiting."
				exit 0
			fi
		fi
	# Check for curl not being installed.
	elif [ $ec -eq 127 ]; then
		echo "ERROR: curl is not installed on this machine! Curl is required to update $script" >&2
		canupdate=0
	# Cover any other exit codes we could possibly get. Not sure what this could be, but worth catching just in case.
	else
		echo 'ERROR: Reaching our updates server failed in an unexpected manner. Please investigate.' >&2
		canupdate=0
	fi
}

# Update the script.
if [ "$1" == "-u" ]; then
	# See if there are any updates or if we can update at all.
	checkforupdates
	# Back up the original script and download the newest version.
	if [ $canupdate -eq 1 ]; then
		echo -n "Updating ${script}..."
		# Find the full path to our script.
		foo=$(which $script)
		# Create a backup, just in case.
		mv $foo ${foo}.old
		# Overwrite our script with the new script captured in checkforupdates()
		echo "$newscript" > $foo
		# Use notes header to verify download's integrity.
		checkup=$(grep '^# Shell script to update Gentoo.' $foo)
		if [ -n "$checkup" ]; then
			rm ${foo}.old
			chmod +rx $foo
			echo -e "done. \n${script} has been updated successfully! Exiting."
			exit 0
		else
			# If download verification fails, revert to original script.
			mv ${foo}.old $foo
			echo 'The Gentoo update script failed to to pass our integrity check after update. Reverted to original version'
			exit 1
		fi
	else
		echo 'Updates have been disabled due to the above error. Exiting.'
		exit 1
	fi
# Print version information.
elif [ "$1" == "-v" ]; then
	echo "GentooUpdate v${rev}"
	exit 0
# Catch any rogue arguments.
elif [ -n "$1" ]; then
	echo "${script}: unrecognized option '${1}'" >&2
	usage >&2
	exit 1
fi

# Silent check for updates to notify user of new version.
# If this fails, send no error messages as it is not needed.
autocheck=$(curl $dl 2>/dev/null | grep "^rev=" 2>/dev/null | cut -d \' -f 2-2 2>/dev/null) 
if [ -n "$autocheck" ] && [ "$autocheck" != "$rev" ]; then
	echo "INFO: A new version of $script is available!"
	echo "Current Version: $rev"
	echo "Updated Version: $autocheck"
	echo "Run $script -u to update to the newest version."
	sleep 3
fi

# Update portage.
echo -e "Beginning rsync of portage.\n"
emerge --sync
echo -e "\nPortage updated, checking for package updates.\n"

# Pass this variable after the portage sync. 
# Our output: 0 = no updates >0 = updates
updates=$(emerge -uDpN world)
checkup=$(echo "$updates" | tail -n+5 | wc -l)
# Check for man pages in updates
checkmp=$(echo "$updates" | grep 'sys-apps/man-pages')
# Check for blocked packages
checkbp=$(echo "$updates" | grep '\[blocks B')

# Checks for updates and exits if we have none available.
if [ $checkup -eq 0 ]; then
        echo 'No updates availalable at this time. Exiting.'
        exit 0
# Checks for blocked packages and prints packages/exits automatically.
elif [ -n "$checkbp" ]; then
	echo 'WARNING: Blocked packages found by portage! Update cannot proceed. Packages found:' >&2
	emerge -uDpN world >&2
	echo -e '\nExiting.' >&2
	exit 1
fi 

# List available updates.
emerge -uDpN world

# A loop to ask if you want to update. All forms of yes/no supported, and unknown responses restart the loop.
loop=1

while [ $loop -eq 1 ]; do
	echo -en "\nWould you like to update Gentoo? (yes/no): "
	read answer

	case $answer in
		y|Y|[Yy][Ee][Ss])
		loop=0
		echo -e "\nUpdating packages in Portage.\n"
		emerge -uDN world
		# run makewhatis -u if man-pages had an update
		if [ -n "$checkmp" ]; then
			echo -ne "\nRunning makewhatis -u for updated man pages..."
			makewhatis -u
			echo 'done!'
		fi
		echo -e "\nChecking Gentoo for package dependency errors.\n"
		revdep-rebuild
		echo -e "\nRemoving all unnecessary distfiles."
		rm -fr /usr/portage/distfiles/*
		echo -e "\nAll distfiles have been deleted! \n\nInvoking etc-update to check for configuration updates.\n"
		etc-update
		echo -e "\nAll finished. Your Gentoo installation has been successfully updated!"
		exit 0
		;;

		n|N|[Nn][Oo])
		loop=0
		echo -e "\nPortage update has been aborted."
		exit 0
		;;

		*)
		echo -e "\nInput not understood. Try again.\n"
		loop=1
		;;
	esac
done
