#!/bin/bash
#customised arch install script for my system
#only on github so I can download it from memory

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

