#!/usr/bin/python -tt
# GentooUpdate.py
# Python script to update Gentoo.
# NOTE: DO NOT REMOVE THE ABOVE LINE! USED FOR SANITY CHECKING! =)
#
# v4.1  - Re-wrote update to find it's valid/rev info dynamically
#       - Added some extra error checking to update function
# v4.02 - Fixed a bug with dist-file removal
# v4.01 - Finished and tested as working. Yey for Python!
# v4.00 - Re-written in Python goodness with much help from David C.
# v3.95 - Added basename catch, made our arg handling better.
# v3.94 - Added usage as output instead of 'Input not understood.'
# v3.93 - Added a check for curl when -u is called
# v3.92 - Added a check to ensure script is being run on Gentoo
# v3.91 - Fixed a formatting issue on revdep-rebuild
# v3.9  - Added auto detection/notification of available updates
#	    - Made the updater much more intelligent
# v3.8  - Added support to stop when package blocks are found
#	    - Misc. formatting changes and small fixes
# v3.72 - Migrated $dl to personal domain
#	    - Added GPL License
# v3.71 - A few small fixes
# v3.7  - Fixed some output stuff
# v3.6  - Added automatic makewhatis -u support
#
# All previous versions were pretty bad. Don't worry about them. =)
#
# Copyright (C) 2008-2009  James Bair <james.d.bair@gmail.com>
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

# Modules
import os
import sys
import tempfile
import urllib
import shutil
import re

# Global variables
# Keep the rev variable on the same line or update revLineNumber!
rev = 4.1
prog = os.path.basename(sys.argv[0])

# Usage
def usage():

	print "Usage: " + prog + " [option]"
	print "If run without an option, it updates the system.\n"
	print "Available Options:"
	print "-v	Prints out the version"
	print "-u	Updates to the newest version"

# Function to remove all files from a directory since
# shutil wipes out the folder too
def wipe_folder(folder):

	# Find all files in the folder
	for i in os.listdir(folder):
		# Get the full path
		file_path = os.path.join(folder, i)
		# If it's a file, delete it
		if os.path.isfile(file_path):
			os.unlink(file_path)

# Function to search for a regex-compatible string, grep style
def findLine(pattern, list=[]):

	# Used to return None if nothing is found at all
	empty = True
	# The line we're looking for
	ourPattern = re.compile(pattern)
	# Check each line for our pattern
	for line in list:
		line.strip()
		ourResult = ourPattern.search(line)
		# Found it! Return it and mark it as non-empty
		if ourResult:
				empty = False
				return line

	# Check if we found anything. Return None if so.
	if empty:
		return None

# Update function, orignally written by David Cantrell
def update_script():

	# Our URL, current file and it's backup
	dl = 'http://www.tsuehpsyde.com/scripts/python/gentooupdate.py'
	dest = os.path.realpath(sys.argv[0])
	backup = "%s.old" % (dest,)

	# Make sure we can overwrite it with an update
	if not os.path.isfile(dest) and not os.access(dest, os.W_OK):
		sys.stderr.write("Do not have write access to %s\n" % (dest,))
		sys.exit(1)

	# Find where tmp should be
	tmpdir = tempfile.gettempdir()

	# Create a tmp dir if it doesn't exist
	if not os.path.isdir(tmpdir):
		os.makedirs(tmpdir, mode=0755)

	# Delete any pre-existing backups (.old)
	if os.path.isfile(backup):
		os.unlink(backup)

	# Rename our script to *.old
	os.rename(dest, backup)
	(fd, newscript) = tempfile.mkstemp(prefix=prog, dir=tmpdir)
	try:
		(filename, headers) = urllib.urlretrieve(dl, newscript)
	except:
		hostname = dl.split('/')[2]
		print "Unable to connect to %s - Exiting." % (hostname,)
		os.unlink(newscript)
		os.rename(backup, dest)
		sys.exit(1)

	# Download the script and store it into a list called lines
	fp = open(newscript, 'r')
	lines = fp.readlines()
	fp.close()

	# Verify our integrity
	valid = findLine('^# Python script to update Gentoo.$',lines)

	# If valid, check to see if it's newer.
	if valid is not None:
		revLine = findLine('^rev = ',lines)

		if revLine is not None:
			# Split the line into name/value
			revLine, newRev = revLine.split('=')

			# Remove whitespace
			newRev = newRev.strip()

			# Need to make our new revision # a float
			newRev = float(newRev)

			# Verify our rev is older than the latest one downloaded
			if rev >= newRev:
				print 'Already updated to the latest version. Exiting.'
				os.unlink(newscript)
				os.rename(backup, dest)
				sys.exit(0)

			# If not, then the line has been moved. Print out message to fix this
		else:
			print 'Unable to find our revision. This is a bug.'

		# Move our new script into place and make it executable
		shutil.move(newscript, dest)
		os.chmod(dest, 0755)

		# Delete the old one, and let everyone know we're done
		os.unlink(backup)
		print "The Gentoo update script has been updated. Exiting."
		sys.exit(0)

	# If not valid, abort.
	else:
		os.unlink(newscript)
		os.rename(backup, dest)
		print "Unable to find our integrity line."
		print "Verify the data at:", dl
		print "Exiting."
		sys.exit(1)

# Check for packages in our updates
# Usage: packagename, listo to check
def isPackageInList(pkg, list=[]):

	for item in list:
		# Returns the byte your string can be found at
		# Gives -1 if it doesn't exist
		if item.find(pkg) != -1:
			return True
	# If we go through all items in the list and don't
	# find anything, return False
	return False

# The actual script itself
def main():

	# Must be root to run this script.
	if os.getuid() != 0:
		sys.stderr.write("This script must be run as root. Exiting.\n")
		sys.exit(1)

	# Must be run on a Gentoo Linux machine only
	#if not os.path.isdir("/usr/portage/profiles/"):
	#	sys.stderr.write("This script is being run on a non-Gentoo system. Exiting.\n")
	#	sys.exit(1)

	# Must be run with one argument or less
	# the len must be two since python counts 0
	if len(sys.argv) > 2:
		usage()
		sys.exit(1)

	# Start work with arguments if we have them
	if len(sys.argv) == 2:
		if sys.argv[1] == "-u":
			update_script()
		elif sys.argv[1] == "-v":
			print "GentooUpdate v%s" % (rev,)
			sys.exit(0)
		else:
			sys.stderr.write(prog + ": unrecognized option '" + sys.argv[1] + "'\n")
			# Not sure how to do >&2 with the following usage in Python =(
			usage()
			sys.exit(1)

	# Update portage.
	print "Beginning rsync of portage."
	os.system("emerge --sync")
	print "Portage updated, checking for package updates."

	# Need to save the output of emerge -uDpN world into a list
	# Create a blank list to save the lines to
	updates = []
	# Run the command itself
	sysCall = os.popen("emerge -uDpN world", "r")

	# Go through and put each line in updates
	for line in sysCall.readlines():
		updates.append(line.strip())

	# The first 4 lines are output from emerge. If we get
	# only 4 lines, no updates are available.
	updatesAvailable = len(updates)
	updatesAvailable -= 4
	if updatesAvailable == 0:
		print '\nNo updates available. Exiting.'
		sys.exit(0)
	else:
		# Strip out the extra four lines and save as our updates list
		updates = updates[4:]

	print '\n', updatesAvailable, 'packages updates found!'

	# See if we have any requirements before simply updating our packages
	# Check for blocked packages
	if isPackageInList('[blocks B', updates):
		print 'WARNING: Blocked packages found by portage! Update cannot proceed. Packages found:'
		for each in updates:
			print each
		sys.exit(1)

	# Check if man pages are going to get updated
	manpageUpdates = False
	if isPackageInList('sys-apps/man-pages', updates):
		manpageUpdates = True

	# The following packages need updates
	# Done using emerge for color preservation
	os.system("emerge -uDpN world")
	print '' # Done for formatting

	# A loop to ask if you want to update. All forms of yes/no supported, and unknown responses restart the loop.
	while True:

		# Ask user if they want to proceed, set text to lowercase
		answer = raw_input("Would you like to update Gentoo? (yes/no): ")
		answer = answer.strip()
		answer = answer.lower()

		# Time to update the system!
		if answer == 'yes':
			print 'Updating packages in portage'
			os.system("emerge -uDN world")

			# If man-pages updated, run makewhatis -u to update it's db
			if manpageUpdates:
				print 'Running makewhatis -u for updated man pages...'
				os.system("makewhatis -u")

			# Check for and fix any dependency issues
			print 'Checking Gentoo for package dependency errors.'
			os.system("revdep-rebuild")

			# Remove all distfiles
			print 'Removing distfiles from system.'
			wipe_folder('/usr/portage/distfiles/')

			print 'All distfiles have been deleted. Invoking etc-update to check for configuration updates.'
			os.system("etc-update")

			print 'All finished! Your Gentoo installation has been successfully updated.'
			sys.exit(0)


		elif answer == 'no':
			print 'Portage update has been aborted.'
			sys.exit(0)
		else:
			print "Input '" + answer + "' not understood. Try again."

# Run main() if ran directly, but halt if ctrl+c is given
if __name__ == "__main__":
	try:
		main()
	except KeyboardInterrupt, e:
		sys.stderr.write("\nCaught SIGINT, Exiting.\n")
		sys.exit(1)
