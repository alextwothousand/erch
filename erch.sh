#!/bin/bash

# stdout function with escaping
function stdout {
	echo -e "$1"
}

# stdinutting without having to hit enter
function stdin {
	if [[ $2 != "" ]]
	then
		read -r "$1" "$2"
	else
		read -r "$1"
	fi
	stdout
}

# terminal formatting
fmtReset="\e[0m"
fmtBold="\e[1m"

# terminal colours
clrFgGreen="\e[32m"

# preamble variables
# full
kbLayout="us"

#empty
userName=""
res=""

# start of script
stdout """$clrFgGreen""""$fmtBold""============================================""$fmtReset"""
stdout """$clrFgGreen""Welcome to the ""$fmtBold""Erch Linux ""$fmtReset""""$clrFgGreen""installer."
stdout "There are a few questions we will have to ask you before proceeding."
stdout "Is this OK? (""$fmtBold""Y""$fmtReset""""$clrFgGreen""/n)"
stdout """$fmtBold""============================================""$fmtReset"""

stdin -n1 res

if [[ $res == "n" || $res == "N" ]]
then
	stdout "Goodbye!"
	exit
fi

dmesg | grep -q "EFI v"    # -q tell grep to output nothing
if [ $? -eq 0 ]     # check exit code; if 0 EFI, else BIOS
then
    efi=true
else
    efi=false
fi

if [[ $efi == true ]]
then
	stdout "Your system supports EFI boot. It is advisable that you proceed with EFI boot."
	stdout "Would you like to use EFI or BIOS? (""$fmtBold""Y""$fmtReset""/n)"

	stdin -n1 res

	if [[ $res == "n" ]]
	then
		efi=false
		stdout "Switching to BIOS mode."
	else
		stdout "Using EFI mode."
	fi
else
	stdout "Using BIOS boot."
fi

stdout "The default keyboard layout is ""$fmtBold""$kbLayout""$fmtReset"". Would you like to change it to something else? (y/""$fmtBold""N""$fmtReset"")"
stdin -n1 res

if [[ $res == "y" ]]
then
	stdout "Please enter the keyboard layout you would like to use."
	read kbLayout
fi

# just for testing purposes. ensures we have sudo permission.
if [ "$EUID" -ne 0 ]
then
	sudo fdisk -l
else
	fdisk -l
fi

diskName=""
while [[ $diskName == "" ]]
do
	stdout "\nWhat is the name of the disk you would like to install Erch Linux on- without prepending the mountpoint?"
	stdout """$fmtBold""Warning! This can have serious repercussions if you pick the incorrect drive!"
	stdout """$fmtBold""Example: sda""$fmtReset"""

	stdin diskName
done

hostName=""
while [[ "${hostName}" == "" ]]
do
	stdout "Please enter a system hostname"
	stdin hostName
done

stdout "OK. That should be all for now. Before we begin, a small disclaimer."

stdout "Erch Linux prefers a minimum of 5GB disk space, plus an extra 1GB for an EFI partition, and the equivalent of your amount of system memory for swap. Are you sure you would like to proceed? (y/N)"
stdin -n1 res
if [[ $res != "y" && $res != "Y" ]]
then
	stdout "Goodbye!"
fi

stdout "Erch is a free and easy to use installer for Arch Linux. If you have retrieved this script from anywhere else other than the official GitHub repository, we will not be able to assist you\n\
with any issues you may have caused by this installer. By using the Erch installer, you agree to our terms & conditions that can be found on our GitHub at https://github.com/alextwothousand/erch"

stdout "Do you agree? (y/N)"
stdin -n1 res
if [[ $res != "y" && $res != "Y" ]]
then
	stdout "Goodbye!"
fi

stdout "Starting installation... This could take roughly from 5-10 minutes, depending on your internet speed."

# create swap partition
(
	echo n
	echo p
	echo 1
	echo
	echo +8G
	echo t
	echo swap
	echo w
	echo q
) | sudo fdisk /dev/"$diskName"

if [[ $efi == true ]]
then
	(
		echo n
		echo p
		echo 2
		echo
		echo +1G
		echo t
		echo
		echo uefi
		echo w
		echo q
	) | sudo fdisk /dev/"$diskName"

	(
		echo n
		echo p
		echo 3
		echo
		echo
		echo w
		echo q
	) | sudo fdisk /dev/"$diskName"

	mkfs.ext4 /dev/"${diskName}"3
else
	(
		echo n
		echo p
		echo 2
		echo
		echo
		echo w
		echo q
	) | sudo fdisk /dev/"$diskName"

	mkfs.ext4 /dev/"${diskName}"3
fi

mkswap /dev/"${diskName}"1

if [[ $efi == true ]]
then
	mount /dev/"${diskName}"3 /mnt
else
	mount /dev/"${diskName}"2 /mnt
fi

swapon /dev/"${diskName}"1

pacstrap /mnt base linux linux-firmware dhcpcd sudo nano grub

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt

ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime

hwclock --systohc

rm -f /etc/locale.gen

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen

echo "LANG=en_US.UTF-8" >> /etc/locale.conf

echo "KEYMAP=""$kbLayout""" >> /etc/vconsole.conf

echo "${hostName}" >> /etc/hostname

echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 ""${hostName}"".localdomain ""${hostName}""" >> /etc/hosts

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

echo "[multilib-testing]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
echo "[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

pacman -Syyu --needed --noconfirm

passwd

if [[ $efi == true ]]
then
	mkdir /efi
	grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
else
	grub-install --target=i386-pc /dev/"${diskName}"2
fi

grub-mkconfig -o /boot/grub/grub.cfg

stdout "Please enter your new user account name:"
stdin userName

useradd "${userName}"
passwd "${userName}"

usermod -aG wheel "${userName}"

pacman -S xfce4 xfce4-goodies --needed --noconfirm
pacman -S lightdm lightdm-gtk-greeter --needed --noconfirm

systemctl enable dhcpcd
systemctl enable lightdm

exit

umount -R /mnt

stdout "Erch has been installed successfully!"
stdout "Please run ""$fmtBold""reboot""$fmtReset"" to boot into your new system."

# stdout grep MemTotal /proc/meminfo | awk '{print $2}' / 1024