#!/bin/bash

#
# Initialization
#

clear

if ! pacman -Qs gum > /dev/null; then
    printf "\n📦 Installing the pkg gum...\n"
    pacman -Sy --noconfirm gum > /dev/null
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

function part_block() {

    BOOT_SIZE=$(gum input --width 120 \
        --value 120 \
        --prompt "👉 Input the size in MB for your BOOT partition: " | head -n 1)

    BOOT_SECTORS=$(($BOOT_SIZE * 1048576 / 512))

    SWAP_SIZE=$(gum input --width 120 \
        --value 32000 \
        --prompt "👉 Input the size in MB for your SWAP partition: " | head -n 1)

    SWAP_SECTORS=$(($SWAP_SIZE * 1048576 / 512))

    BOTH_SECTORS=$(($BOOT_SECTORS + $SWAP_SECTORS + 4098))

    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${BLK} > /dev/null
      g # new GPT
      n # new partition
      1 # default partition 1
        # default - start at beginning of disk
      +${BOOT_SIZE}M # MB BOOT parttion
      n # new partition
      2 # default partion 2
        # default, start immediately after preceding partition
      +${SWAP_SIZE}M # MB SWAP parttion
      t # set type
      2 # of part 2
      19 # swap type
      n # new partition
      3 # partion number 3
      $BOTH_SECTORS
        # default, extend partition to end of disk
      w # write the partition table
EOF

    printf "✅ BOOT, SWAP & ROOT partitions were created!\n\n"

    return 0
}


if ! part_block; then
    exit 1
fi