#!/bin/bash
# Script to show the changes between config files for Gentoo
# v0.1 - Initial script
# Jim Bair 4/21/2009
newConfigs=$(find /etc/* -type f -name '._cfg0000_*' -print)

if [ -n "$newConfigs" ]; then
	echo -e "Found new config files. Proceeding.\n"
	# Do in a loop for multiple files
	for i in $newConfigs; do
		j=$(echo $i | sed 's/._cfg0000_//')
		# Make sure our files exist and diff them
		if [ -s "$i" -a -s "$j" ]; then
			diff $i $j
			# Pause between config files
			read -p "Showing proposed changes for ${j} "
		# If we get here, something is broken with our syntax
		else
			echo "ERROR: $i or $j does not exist! Exiting." >&2
			exit 1
		fi
	done
	echo "All proposed config changes shown. Exiting."
# If $newConfigs is null, just exit out as we have no updates
else
	echo "No new updates to diff against. Exiting."
fi
exit 0
