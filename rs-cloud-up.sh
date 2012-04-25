#!/bin/bash
# A simple script to upgrade a Rackspace Cloud instance from Gentoo 11.0 to
# the latest, stable release. Upgrades both world as well as rebuilds with
# the latest kernel, using a few EasyGentoo utils along the way.
 
cd /tmp/

# Get our run() func - super useful in shell scripts.
if [ ! -s run.sh ]; then
    wget https://raw.github.com/tsuehpsyde/misc/master/bash/run.sh &>/dev/null
    if [ $? -ne 0 ]; then
        echo "Unable to fetch our run() function. Exiting." >&2
        exit 1
    fi
fi

source run.sh
run rm -f run.sh

# Rackspace doesn't install portage by default - this is notably faster than an emerge --sync.
if [ ! -d "/usr/portage/" ]; then
    echo -n "Portage not installed! Fetching latest portage tarball from Rackspace..."
    run wget -q http://mirror.rackspace.com/gentoo/snapshots/portage-latest.tar.bz2
    echo -en "done.\nInstalling portage..."
    run tar xjf portage-latest.tar.bz2 -C /usr
    run rm -f portage-latest.tar.bz2
    echo 'done.'
    echo "Portage installation completed."
else
    echo "Portage already installed - skipping installation."
fi

# Fetch our updater and grab today's updates and rebuild.
cd /usr/local/sbin/
for script in gentooupdate.py kernel-upgrade.sh; do
    [ -s "${script}" ] && continue
    echo -n "Fetching ${script}..."
    wget https://raw.github.com/tsuehpsyde/easygentoo/master/${script} &>/dev/null
    if [ $? -eq 0 ]; then
        run chmod +x ${script}
        echo 'done.'
    else
        echo 'failed.'
        exit 1
    fi
done

# Upgrade the OS and the kernel
gentooupdate.py
kernel-upgrade.sh

# All done
exit 0
