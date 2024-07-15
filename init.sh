#!/bin/bash

#
# Initializing
#

GUM_CMD=gum

function get_deps() {
    if ! pacman -Qs gum > /dev/null; then
        printf "\n📦 Installing dependencies...\n"
        pacman -Sy --noconfirm jq curl > /dev/null
        printf "\n✅ Successfully installed jq and curl!\n"
    fi
}

function get_gum() {
    GUM_FILE_NAME=$(jq -r '.[0].assets[] | select(.name | test("gum_.*_Linux_x86_64.tar.gz")) .name' ${GUM_CACHED_FILE} | 
        head -n 1)
    GUM_URL=$(jq -r '.[0].assets[] | select(.name | test("gum_.*_Linux_x86_64.tar.gz")) .browser_download_url' ${GUM_CACHED_FILE} | 
        head -n 1)

    OLD_GUM_DIR=${GUM_FILE_NAME%.tar.gz}
    NEW_GUM_DIR=./assets/gum_${GUM_LATEST}

    mkdir $NEW_GUM_DIR &> /dev/null

    curl -L ${GUM_URL} -o ./assets/${GUM_FILE_NAME} &> /dev/null
    tar -xf ./assets/${GUM_FILE_NAME} -C ./assets/ &> /dev/null
    mv ./assets/${OLD_GUM_DIR}/gum $NEW_GUM_DIR &> /dev/null
    rm -rf ./assets/${OLD_GUM_DIR} &> /dev/null
    rm ./assets/${GUM_FILE_NAME} &> /dev/null

    return 0
}

function set_gum() {

    REPO_URL=https://api.github.com/repos/charmbracelet/gum/releases
    GUM_CACHED_FILE=assets/gum_releases.json

    # Check if we've ran this once before
    if ! test -f "$GUM_CACHED_FILE"; then
        curl -sS ${REPO_URL} > ${GUM_CACHED_FILE}
        GUM_CACHED_VER=$(jq -r '.[] | .name' ${GUM_CACHED_FILE} | head -n 1)
        GUM_LATEST=${GUM_CACHED_VER}
    else 
        GUM_CACHED_VER=$(jq -r '.[] | .name' ${GUM_CACHED_FILE} | head -n 1)
        GUM_LATEST=$(curl -sS ${REPO_URL} | jq -r '.[] | .name' | head -n 1)
    fi

    GUM_BIN=./assets/gum_${GUM_LATEST}/gum

    # Check if the last cached version matches:
    if [ $GUM_CACHED_VER == $GUM_LATEST ]; then
        # Check if we have the bin...
        if ! test -f ${GUM_BIN}; then 
            printf "\n❌ \`gum\` wasn't found. Obtaining...\n\n"
            if ! get_gum; then
                exit 1
            fi
        fi
    else
        # Versioning difference detected, rm and update
        printf "\n👀 New \`gum\` release detected. Updating...\n\n"
        rm -rf ./assets/gum_${GUM_CACHED_VER}
        curl -sS ${REPO_URL} > ${GUM_CACHED_FILE}
        if ! get_gum; then
            exit 1
        fi
    fi
    
    GUM_CMD=${GUM_BIN}
    
    return 0
}

function init() {

    clear

    # Ensure privs are met...
    if [ $(id -u) != 0 ]; then
        printf "\n❌ Script not ran as root. Exiting.\n\n"
        exit 1
    fi

    # Ensure a valid network connection...
    if ! ping -c 1 -w 2 google.com &> /dev/null; then 
        printf "\n❌ No internet connection. Exiting.\n\n"
        exit 1
    fi

    # Ensure this dir exists...
    mkdir -p ./assets

    if command -v pacman &> /dev/null; then 
        if ! get_deps; then
            exit 1
        fi
    fi
    
    # Ensure `gum` is present...
    if ! set_gum; then
        exit 1
    fi
    
    return 0
}

#
# Selecting
#

function sel_block() {

    clear

    local disks=$(lsblk -d -n -oNAME,RO | grep '0$' | awk {'print $1'})
    DEV_BLK=$($GUM_CMD choose --limit 1 --header "Device block to partition:" <<< "$disks")
    if [[ -z "$DEV_BLK" ]]; then
        printf "\n❌ No valid block device was selected...\n\nTry again?\n\n"
        return 1
    fi

    BLK=$"/dev/$DEV_BLK"

    if $GUM_CMD confirm "So, we're installing Gentoo on $BLK?"; then
        printf "\n⌛ Time to partition $BLK...\n\n"
    else
        sel_block
    fi

    return 0
}

#
# Partitioning
#

function part_block() {

    BOOT_SIZE=$($GUM_CMD input --width 120 \
        --value 120 \
        --prompt "👉 Input the size in MB for your BOOT partition: " | head -n 1)

    BOOT_SECTORS=$(($BOOT_SIZE * 1048576 / 512))

    SWAP_SIZE=$($GUM_CMD input --width 120 \
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

#
# Formatting
#

function fmt_parts() {
    BOOT=$(printf "%sp1" "$BLK")
    SWAP=$(printf "%sp2" "$BLK")
    ROOT=$(printf "%sp3" "$BLK")

    mkfs.vfat -F 32 ${BOOT} > /dev/null
    printf "✅ BOOT was formatted to Fat32!\n\n"

    mkswap ${SWAP} > /dev/null
    printf "✅ SWAP was made!\n\n"

    mkfs.btrfs -f ${ROOT} > /dev/null
    printf "✅ ROOT was formatted to BTRFS!\n\n"
}


#
# Preparing Base FS
#

function prep_base() {

    clear

    MNT=$"/mnt/gentoo"

    mkdir --parents ${MNT}
    mount ${ROOT} ${MNT}

    btrfs subvolume create ${MNT}/@ 
    btrfs subvolume create ${MNT}/@home                                                                 
    btrfs subvolume create ${MNT}/@snapshots

    umount -l ${MNT}

    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@ ${ROOT} ${MNT}

    mkdir -p ${MNT}/boot/efi
    mount ${BOOT} ${MNT}/boot/efi

    swapon ${SWAP} 

    # TODO: Also cp ./assets
    # Into `${MNT}/tmp/installer`
    cp chroot.sh ${MNT}

    cd ${MNT}

    # TODO: Pull the latest version
    wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20240707T170407Z/stage3-amd64-openrc-20240707T170407Z.tar.xz 
    
    tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

    cp --dereference /etc/resolv.conf ${MNT}/etc/

    mount --types proc /proc ${MNT}/proc
    mount --rbind /sys ${MNT}/sys
    mount --make-rslave ${MNT}/sys
    mount --rbind /dev ${MNT}/dev
    mount --make-rslave ${MNT}/dev
    mount --bind /run ${MNT}/run
    mount --make-slave ${MNT}/run

    chroot ${MNT} /bin/bash -c "./chroot.sh"
}

#
#  Heart of it all
#

function installer() {

    if ! init; then
        exit 1
    fi

    if ! sel_block; then
        exit 1
    fi

    if ! part_block; then
        exit 1
    fi

    if ! fmt_parts; then
        exit 1
    fi
    
    if ! prep_base; then
        exit 1
    fi
}

installer
