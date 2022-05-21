#!/bin/bash
#customised arch install script for my system
#only on github so I can download it from memory
pacman -Sy dialog --noconfirm
clear
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

swap=$(dialog --stdout --inputbox "Enter swap amount in GiB (0 for none)" 0 0) || exit 1
clear
: ${swap:?"user cannot be empty"}

echo "hostname:" $hostname
echo "username:" $user
echo "password:" $password
echo "device:" $device
if [ $swap == 0 ]; then
    echo "Swap Disabled"
else
    echo "swap:" $swap"GiB"
fi

timedatectl set-ntp true


if [ $swap == 0 ]; then
    # Setup the disk and partitions

    parted --script "${device}" -- mklabel gpt \
    mkpart ESP fat32 1Mib 300MiB \
    set 1 boot on \
    mkpart primary ext4 300Mib 100%

    part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
    part_root="$(ls ${device}* | grep -E "^${device}p?2$")"

    wipefs "${part_boot}"
    wipefs "${part_root}"

    mkfs.vfat -F32 "${part_boot}"
    mkfs.ext4 "${part_root}"

    mount "${part_root}" /mnt
    mkdir /mnt/boot
    mount "${part_boot}" /mnt/boot
else
    swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
    swap_end=$(( $swap * 1024 + 300 ))MiB

    parted --script "${device}" -- mklabel gpt \
    mkpart ESP fat32 1Mib 300MiB \
    set 1 boot on \
    mkpart primary linux-swap 300MiB ${swap_end} \
    mkpart primary ext4 ${swap_end} 100%

    part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
    part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
    part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

    wipefs "${part_boot}"
    wipefs "${part_swap}"
    wipefs "${part_root}"

    mkfs.vfat -F32 "${part_boot}"
    mkswap "${part_swap}"
    mkfs.ext4 "${part_root}"

    swapon "${part_swap}"
    mount "${part_root}" /mnt
    mkdir /mnt/boot
    mount "${part_boot}" /mnt/boot
fi

#edit pacman for colour(useless) and parallel downloads in the installer iso for a faster install
sed -i 's/#Parallel/Parallel/g' /etc/pacman.conf
sed -i 's/#Color/Color/g' /etc/pacman.conf

#install initial packages with pacstrap
pacstrap /mnt base linux linux-firmware nvidia-dkms zsh nano grub efibootmgr os-prober neofetch sudo --noconfirm

#generate fstab file
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab

#set hostname, locale and timezone
echo "${hostname}" > /mnt/etc/hostname
echo "LANG=en_GB.UTF-8" > /mnt/etc/locale.conf
echo "en_GB.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "en_GB ISO-8859-1" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt timedatectl set-timezone Europe/London

#set colour and parallel downloads on the new install
sed -i 's/#Parallel/Parallel/g' /mnt/etc/pacman.conf
sed -i 's/#Color/Color/g' /mnt/etc/pacman.conf

#install grub
arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/g' /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

#set hosts file
echo "127.0.0.1	localhost" >> /mnt/etc/hosts
echo "::1		localhost" >> /mnt/etc/hosts
echo "127.0.1.1	${hostname}" >> /mnt/etc/hosts

#create user and change root user password
arch-chroot /mnt useradd -mU -s /usr/bin/zsh -G wheel "$user"
arch-chroot /mnt chsh -s /usr/bin/zsh
echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt
reboot
