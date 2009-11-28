#!/usr/bin/python
# v1.0 - Development
# A quick script I put together to upgrade a Gentoo system
# using genkernel. I thought genkernel used to do this, but
# I could be totally wrong. Either way, when I use genkernel
# (which I only end up with after using Quickstart), I don't
# want to think about the kernel. So, to automate the
# upgrade/rebuild process, we have this. Change the flags as
# you see fit. --static is just a personal preference.
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

import commands
import os
import sys

# Find our kernels
sys.stdout.write('Finding our kernels...')
sys.stdout.flush()

status, text = commands.getstatusoutput('eselect kernel list')
if status is not 0:
        sys.stderr.write("\nUnable to run eselect.\n")
        sys.exit(1)

sys.stdout.write("done.\n")
sys.stdout.flush()

# Split by lines, find current (contains *)
sys.stdout.write('Finding our current kernel...')
sys.stdout.flush()

text = text.split('\n')
current = None
for line in text:
        if '*' in line:
                current = line
if current is None:
        sys.stderr.write("\nUnable to find current kernel.\n")
        sys.exit(1)

sys.stdout.write("done.\n")
sys.stdout.flush()

# See if we need to update (last line is newest)
latest = text[-1]
if current == latest:
        sys.stdout.write("No newer kernels available.\n")
        sys.exit(0)

# Grab the number from the 1st item on the line
latest = latest.split()[0]
latest = latest[1]

# Set our kernel to the latest
status, text = commands.getstatusoutput('eselect kernel set %s' % (latest,))
if status is not 0:
        sys.stderr.write("Unable to set kernel.\n")
        sys.exit(1)

# Build and install it
os.system('genkernel --install --mountboot --bootloader=grub --static all')
sys.exit(0)
