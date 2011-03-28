#!/usr/bin/python -tt
# GentooUpdate.py
# Python script to update Gentoo.
# NOTE: DO NOT REMOVE THE ABOVE LINE! USED FOR SANITY CHECKING! =)
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
import re
import shutil
import sys
import tempfile
import urllib

# Global variables
__author__ = "James Bair"
__date__ = "Mar. 28, 2011"
rev = 4.43

# Begin our defs
def echo(string=''):
    """
    Function to emulate echo -en type functionality since
    print acts weird at times and py3k changes print as well.
    """
    sys.stdout.write(string)
    sys.stdout.flush()

def usage(prog):
    """
    Simple usage function. Builds and returns a usage string.
    """
    usage = "Usage: " + prog + " [option]\n"
    usage = usage + "If run without an option, it updates the system.\n\n"
    usage = usage + "Available Options:\n"
    usage = usage + "-v    Prints out the version\n"
    usage = usage + "-u    Updates to the newest version\n"
    return usage

def wipe_folder(folder=''):
    """
    Function to remove all files from a directory since
    shutil wipes out the folder too. Made to wipe out dist
    files quickly since the built-in from Portage is slow.
    """
    # Find all files in the folder
    for i in os.listdir(folder):
        # Get the full path
        file_path = os.path.join(folder, i)
        # If it's a file, delete it
        if os.path.isfile(file_path):
            os.unlink(file_path)

def findLine(pattern='', list=[]):
    """
    Function to search for a regex-compatible string, grep style
    Used to return None if nothing is found at all
    """
    # The line we're looking for
    ourPattern = re.compile(pattern)
    # Check each line for our pattern
    for line in list:
        line.strip()
        ourResult = ourPattern.search(line)
        # Found it! Return it and mark it as non-empty
        if ourResult:
            return line

    # If we found nothing, return None
    return None

def findMissingUpdates():
    """
    Function to search for updates that 'emerge -uDaN world' misses
    """
    # Check for any missed updates in portage
    echo('\nChecking for any updates portage missed...')
    missedUpdates = []
    secondPass = os.popen("emerge -ep world", "r")
    for line in secondPass.readlines():
        if ' U ' in line:
            missedUpdates.append(line.strip())
    echo('done.\n\n')
    if missedUpdates:
        emergeMe = []
        updatesNum = len(missedUpdates)
        if updatesNum == 1:
            echo('Found the following missed update:\n')
        else:
            echo('Found the following %s missed updates:\n' % (updatesNum,))

        for line in missedUpdates:
            package = line.split()[3]
            echo('%s\n' % (package,))
            emergeMe.append(package)
            echo('\nUpdating the above packages.\n\n')
            for package in emergeMe:
                os.system('emerge -u =%s' % (package,))
    else:
        echo('No missed packages found.\n')


def update_script(prog):
    """
    Function to update this script, gentooupdate.py.
    Originally wrote by David Cantrell.
    """
    # Our URL, current file and it's backup
    dl = 'http://github.com/tsuehpsyde/easygentoo/raw/master/gentooupdate.py'
    dest = os.path.realpath(__file__)
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
        echo("Unable to connect to %s - Exiting." % (hostname,))
        os.unlink(newscript)
        os.rename(backup, dest)
        sys.exit(1)

    # Download the script and store it into a list called lines
    fp = open(newscript, 'r')
    lines = fp.readlines()
    fp.close()

    # Verify our integrity
    valid = findLine('^# Python script to update Gentoo.$', lines)

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
                echo("%s is already up-to-date.\n" % (prog,))
                os.unlink(newscript)
                os.rename(backup, dest)
                sys.exit(0)

            # If not, then the line has been moved. Print out message to fix this
        else:
            sys.stderr.write("Unable to find the version on the newly downloaded script.\n")
            sys.exit(1)

        # Move our new script into place and make it executable
        shutil.move(newscript, dest)
        os.chmod(dest, 0755)

        # Delete the old one, and let everyone know we're done
        os.unlink(backup)
        echo("You have upgaded %s from version %s to %s.\n" % (prog, rev, newRev))
        sys.exit(0)

    # If not valid, abort.
    else:
        os.unlink(newscript)
        os.rename(backup, dest)
        sys.stderr.write("Unable to find our integrity line.\n")
        sys.stderr.write("Please verify the data here: %s\n" % (dl,))
        sys.exit(1)

# The actual script itself
def main():

    # Variables
    prog = os.path.basename(__file__)
    manpageUpdates = False

    # Must be root to run this script.
    if os.getuid() != 0:
        sys.stderr.write("This script must be run as root. Exiting.\n")
        sys.exit(1)

    # Must be run on a Gentoo Linux machine only
    if not os.path.isdir("/usr/portage/profiles/"):
        sys.stderr.write("This script is being run on a non-Gentoo system. Exiting.\n")
        sys.exit(1)

    # Must be run with one argument or less
    # the len must be two since python counts 0
    if len(sys.argv) > 2:
        echo(usage(prog))
        sys.exit(1)

    # Start work with arguments if we have them
    if len(sys.argv) == 2:
        if sys.argv[1] == "-u":
            update_script(prog)
        elif sys.argv[1] == "-v":
            echo("GentooUpdate v%s\n" % (rev,))
            sys.exit(0)
        else:
            sys.stderr.write("%s: unrecognized option '%s'\n" % (prog, sys.argv[1]))
            sys.stderr.write(usage(prog))
            sys.exit(1)

    # Update portage.
    echo("Beginning rsync of portage.\n\n")
    os.system("emerge --sync")
    echo("\nPortage updated, checking for package updates.")

    # Need to save the output of emerge -uDpN world into a list
    # Create a blank list to save the lines to
    updates = []
    # Run the command itself
    sysCall = os.popen("emerge -uDpN world", "r")

    # Go through and put each line in updates
    for line in sysCall.readlines():
        updates.append(line.strip())

    # Find the # of lines
    updatesAvailable = len(updates)

    # Check our updates for gotchas
    for line in updates:
        # Do not count the eselect news lines
        if 'Use eselect news to read news items' in line:
            updatesAvailable -= 4
            continue
        # Check if man pages are going to get updated
        elif 'sys-apps/man-pages' in line:
            manpageUpdates = True
        # Stop if we have blockers.
        elif '[blocks B' in line:
            sys.stderr.write('WARNING: Blocked packages found by portage! Update cannot proceed. Packages found:\n')
            for update in updates:
                sys.stderr.write("%s\n" % (update,))
            sys.exit(1)

    # The first 4 lines are output from emerge. If we get
    # only 4 lines, no updates are available.
    updatesAvailable -= 4

    # Check if we have any updates.
    if updatesAvailable == 0:
        echo("\n\nNo updates found.\n")
	# This is a hack. This needs to do all the revdep-rebuild stuff
	# Need to make those bits modular and check for a return from
	# this function.
        findMissingUpdates()
        sys.exit(0)
    # Just in case we get -1 or something.
    elif updatesAvailable < 0:
        sys.stderr.write("\nERROR: Something has gone wrong when checking for available updates.\n")
        sys.stderr.write("Length value given: %d" % (updatesAvailable,))
        sys.stderr.write("\nValues in list:\n\n")
        count = 0
        for i in updates:
            count += 1
            sys.stderr.write("Item #%s': %s\n" % (count, i))
        sys.exit(1)

    # Correct grammar is always nice. =)
    if updatesAvailable == 1:
        echo("\n\n1 package update found!\n")
    else:
        echo("\n\n%s package updates found!\n" % (updatesAvailable,))

    # The following packages need updates
    # Done using emerge for color preservation
    os.system("emerge -uDpN world")
    echo('\n') # Done for formatting

    # A loop to ask if you want to update. All forms of yes/no supported, and unknown responses restart the loop.
    while True:

        answer = raw_input("Would you like to update Gentoo? (yes/no): ")
        answer = answer.strip()
        answer = answer.lower()

        # Time to update the system!
        if answer == 'yes' or answer == 'y':
            echo('Updating packages in portage\n')
            os.system("emerge -uDN world")

            # Check for missed updates
            findMissingUpdates()

            # Check for and fix any dependency issues
            echo('\nChecking Gentoo for package dependency errors.\n\n')
            os.system("revdep-rebuild")

            # Remove all distfiles
            echo('\nRemoving distfiles from system...')
            wipe_folder('/usr/portage/distfiles/')
            echo('done!\n\n')

            # Check for cofiguration updates
            echo('Invoking etc-update to check for configuration updates.\n\n')
            os.system("etc-update")

            # If man-pages updated, run makewhatis -u to update it's db
            if manpageUpdates:
                echo('Running makewhatis -u for updated man pages...')
                os.system("makewhatis -u")
                echo('done!\n')

            echo('\nAll finished! Your Gentoo installation has been successfully updated.\n')
            sys.exit(0)

        # Looks like we had second thoughts.
        elif answer == 'no' or answer == 'n':
            echo('Portage update has been aborted.\n')
            sys.exit(0)

        # Anything else is invalid.
        else:
            echo("Input '%s' not understood. Try again.\n\n" % (answer,))

# Run main() if ran directly, but halt if ctrl+c is given
if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt, e:
        sys.stderr.write("\nCaught SIGINT, Exiting.\n")
        sys.exit(1)
