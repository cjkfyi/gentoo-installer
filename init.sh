#!/bin/bash

#
# Initialization
#

# Check if gum is installed, else add it.
if ! pacman -Qs gum > /dev/null 2>&1; then
    echo "📦 Installing the pkg gum..."
    pacman -Sy --noconfirm gum > /dev/null 2>&1
    echo "✅ Successfully installed gum!"
fi

#
# Partition Disk
#

function sel_block() {
    local disks=$(lsblk -d -n -oNAME,RO | grep '0$' | awk {'print $1'})
    DEVBLOCK=$(gum choose --limit 1 --header "Device block to partition:" <<< "$disks")

    if [[ -z "$DEVBLOCK" ]]; then
        printf "\n❌ No valid block device was selected...\n\nTry again?\n\n"
        return 1
    fi

    if gum confirm "So, we're installing Gentoo on $DEVBLOCK?"; then
        printf "✅ Let's now partition /dev/$DEVBLOCK!\n\n"
    else
        sel_block
    fi

    return 0
}

if ! sel_block; then
    exit 1 
fi

function fde_opt() {
    gum confirm "Want to perform a Full Disk Encryption setup?" && 
        echo "Too bad, try again later..." || 
        echo "That's what I thought, too lazy anyways..."
}

if ! fde_opt; then
    exit 1 
fi
