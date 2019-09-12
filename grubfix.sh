#!/bin/bash
# Because Gigabyte nukes my grub install with each firmware update on my
# X570 I AORUS PRO WIFI board, and my 3900X seems to need many of those.
mount /dev/nvme0n1p7 /mnt/gentoo
mount /dev/nvme0n1p6 /mnt/gentoo/boot
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
chroot /mnt/gentoo grub-install --target=x86_64-efi --efi-directory=/boot 
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
