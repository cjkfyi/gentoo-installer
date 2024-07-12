#!/bin/bash

#
# Initialization
#

clear

# Check if gum is installed, else add it.
if ! pacman -Qs gum > /dev/null 2>&1; then
    printf "\n📦 Installing the pkg gum...\n"
    pacman -Sy --noconfirm gum > /dev/null 2>&1
    printf "\n✅ Successfully installed gum!\n"
fi

#
# Partition Disk
#

function sel_block() {
    clear

    local disks=$(lsblk -d -n -oNAME,RO | grep '0$' | awk {'print $1'})
    DEV_BLK=$(gum choose --limit 1 --header "Device block to partition:" <<< "$disks")

    if [[ -z "$DEV_BLK" ]]; then
        printf "\n❌ No valid block device was selected...\n\nTry again?\n\n"
        return 1
    fi

    BLK=$"/dev/$DEV_BLK"

    if gum confirm "So, we're installing Gentoo on $BLK?"; then
        printf "\n⌛ Time to partition $BLK...\n\n"
    else
        sel_block
    fi

    return 0
}

if ! sel_block; then
    exit 1 
fi

#

function fde_start() {
    printf "\nFDE PROCESS IS STARTING\n"
    return 0
}

function fde_opt() {

    if gum confirm "Want to perform a Full Disk Encryption setup?"; then
        printf "👻 FDE isn't implemented yet, carry on...\n"
        part_block
    else
        printf "👻 FDE isn't implemented yet, carry on...\n"
        part_block
    fi

    return 0
}

if ! fde_opt; then
    exit 1 
fi

# 

function part_block() {

    BOOT_SIZE=$(gum input --width 120 \
        --value 120 \
        --prompt "👉 Input the size in MB for your BOOT partition: " | head -n 1)

    SWAP_SIZE=$(gum input --width 120 \
        --value 32000 \
        --prompt "👉 Input the size in MB for your SWAP partition: " | head -n 1)

    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${BLK}
      o # clear the in memory partition table
      n # new partition
      p # primary partition
      1 # partition number 1
        # default - start at beginning of disk 
      +${BOOT_SIZE}M # MB BOOT parttion
      n # new partition
      p # primary partition
      2 # partion number 2
        # default, start immediately after preceding partition
      +${SWAP_SIZE}M # MB SWAP parttion
      t # set the type
      L # Linux swap
      n # new partition
      p # primary partition
      3 # partion number 3
      +$(($BOOT_SIZE + $SWAP_SIZE + 4096))M # MB ROOT parttion
        # default, extend partition to end of disk
      w # write the partition table
      q # and we're done
EOF

    printf "✅ BOOT, SWAP & ROOT partitions were created!\n\n"

    return 0
}


if ! part_block; then
    exit 1
fi