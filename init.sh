#!/bin/bash

#
# Initializing
#

GUM_CMD=gum

# Install dependencies
function get_deps() {
    if ! pacman -Qs jq > /dev/null; then
        printf "\n📦 Installing the pkg \`jq\`...\n"
        pacman -Sy --noconfirm jq  > /dev/null
        printf "\n✅ Successfully installed \`jq\`!\n"
    fi
    if ! pacman -Qs curl > /dev/null; then
        printf "\n📦 Installing the pkg \`curl\`...\n"
        pacman -Sy --noconfirm curl > /dev/null
        printf "\n✅ Successfully installed \`curl\`!\n"
    fi

    return 0
}

# Fetch gum bin
function get_gum() {
    GUM_FILE_NAME=$(jq -r '.[0].assets[] | select(.name | test("gum_.*_Linux_x86_64.tar.gz")) .name' ${GUM_CACHED_FILE} | 
        head -n 1)
    GUM_URL=$(jq -r '.[0].assets[] | select(.name | test("gum_.*_Linux_x86_64.tar.gz")) .browser_download_url' ${GUM_CACHED_FILE} | 
        head -n 1)

    OLD_GUM_DIR=${GUM_FILE_NAME%.tar.gz}
    NEW_GUM_DIR=./assets/gum_${GUM_LATEST}

    mkdir $NEW_GUM_DIR > /dev/null 2>&1

    curl -L ${GUM_URL} -o ./assets/${GUM_FILE_NAME} > /dev/null 2>&1
    tar -xf ./assets/${GUM_FILE_NAME} -C ./assets/ > /dev/null 2>&1
    mv ./assets/${OLD_GUM_DIR}/gum $NEW_GUM_DIR > /dev/null 2>&1
    rm -rf ./assets/${OLD_GUM_DIR} > /dev/null 2>&1
    rm ./assets/${GUM_FILE_NAME} > /dev/null 2>&1

    return 0
}

# Establish bin location
function set_gum() {

    REPO_URL=https://api.github.com/repos/charmbracelet/gum/releases
    GUM_CACHED_FILE=./assets/gum_releases.json

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
        # Versioning difference detected, rm and update...
        printf "\n👀 New \`gum\` release detected. Updating...\n\n"
        rm -rf ./assets/gum_${GUM_CACHED_VER} > /dev/null 2>&1
        curl -sS ${REPO_URL} > ${GUM_CACHED_FILE} > /dev/null 2>&1
        if ! get_gum; then
            exit 1
        fi
    fi

    # Set gum bin loc
    GUM_CMD=${GUM_BIN}
    
    return 0
}

# Initialization
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

    # Ensure dependencies are installed...
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
# Block Selection
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
        if ! sel_block; then
            exit 1
        fi
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
    if [[ -z "$DEV_BLK" ]]; then
        printf "\n❌ No valid block device was selected...\n\nTry again?\n\n"
        return 1
    fi
    
    BOOT_SECTORS=$(($BOOT_SIZE * 1048576 / 512))

    SWAP_SIZE=$($GUM_CMD input --width 120 \
        --value 32000 \
        --prompt "👉 Input the size in MB for your SWAP partition: " | head -n 1)

    SWAP_SECTORS=$(($SWAP_SIZE * 1048576 / 512))

    BOTH_SECTORS=$(($BOOT_SECTORS + $SWAP_SECTORS + 4098))

    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${BLK} > /dev/null 2>&1
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

    mkfs.vfat -F 32 ${BOOT} > /dev/null 2>&1
    printf "✅ BOOT was formatted to Fat32!\n\n"

    mkswap ${SWAP} > /dev/null 2>&1
    printf "✅ SWAP was made!\n\n"

    mkfs.btrfs -f ${ROOT} > /dev/null 2>&1
    printf "✅ ROOT was formatted to BTRFS!\n\n"

    return 0
}

#
# Preparing Base FS
#

function cp_scripts() {

    cp chroot.sh ${MNT} > /dev/null 2>&1
    cp ${GUM_BIN} ${MNT} > /dev/null 2>&1

    printf "✅ Copied over required assets!\n\n"

    return 0
}

#

function ext_base() {

    $GUM_CMD spin --spinner line --title "Extracting the base fs..." -- \
        tar xpvf ./assets/stage3-*.tar.xz -C "${MNT}" --xattrs-include='*.*' --numeric-owner 

    printf "✅ Extracted the base fs!\n\n"

    return 0
}

#

function get_base() {

    BASE_IDX_LOC=./assets/stage3.html

    BASE_IDX_PARAMS=amd64/autobuilds/current-stage3-amd64-openrc
    BASE_IDX_URL=https://mirrors.mit.edu/gentoo-distfiles/releases/${BASE_IDX_PARAMS}/

    # Curl the latest version of the amd64 open
    curl -L ${BASE_IDX_URL} -o ${BASE_IDX_LOC} > /dev/null 2>&1

    IDX_FILE_NAME=$(grep -o '<a href="[^">]*"' ${BASE_IDX_LOC} | cut -d'"' -f2- | grep '.tar.xz"')
    # Process the name of the latest file we're looking for...
    BASE_FILE_NAME=${IDX_FILE_NAME%\"}
    BASE_LOC=./assets/

    NEW_BASE_FILE=./assets/${BASE_FILE_NAME}

    BASE_FILE_URL=${BASE_IDX_URL}${BASE_FILE_NAME}

    # Use glob pattern to match files starting with "stage3-"
    OLD_BASE_LOC=$(find "./assets/" -maxdepth 1 -name stage3-*)
    OLD_BASE_FILE=${OLD_BASE_LOC#./assets/}

    # If we haven't ran this before...
    if test -z "$OLD_BASE_LOC"; then

        $GUM_CMD spin --spinner line --title "Downloading the base fs..." -- \
            curl -L ${BASE_FILE_URL} -o ${NEW_BASE_FILE}

        printf "✅ Downloaded the latest stage3 tarball!\n\n"

        return 0
    fi

    # Check if the last cached version matches:
    if ! [ $OLD_BASE_FILE == $BASE_FILE_NAME ]; then

        rm ${OLD_BASE_LOC}
        
        $GUM_CMD spin --spinner line --title "Downloading the base fs..." -- \
            curl -L ${BASE_FILE_URL} -o ${NEW_BASE_FILE}
        printf "✅ Downloaded the latest stage3 tarball!\n\n"
    else 
        printf "✅ Reusing our latest stage3 tarball!\n\n"
    fi

    return 0
}

#

function prep_base() {

    MNT=$"/mnt/gentoo"

    mkdir --parents ${MNT} > /dev/null 2>&1
    mount ${ROOT} ${MNT} > /dev/null 2>&1

    btrfs subvolume create ${MNT}/@ > /dev/null 2>&1
    btrfs subvolume create ${MNT}/@home > /dev/null 2>&1
    btrfs subvolume create ${MNT}/@snapshots > /dev/null 2>&1

    umount -l ${MNT} > /dev/null 2>&1

    printf "✅ Sub-volumes were created!\n\n"

    BTR_ROOT_OPTS="defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@"
    mount -t btrfs -o ${BTR_ROOT_OPTS} ${ROOT} ${MNT} > /dev/null 2>&1

    mkdir -p ${MNT}/boot/efi > /dev/null 2>&1
    mount ${BOOT} ${MNT}/boot/efi > /dev/null 2>&1

    swapon ${SWAP} > /dev/null 2>&1

    if ! cp_scripts; then
        exit 1
    fi

    if ! get_base; then
        exit 1
    fi

    if ! ext_base; then
        exit 1
    fi
    
    cd ${MNT} > /dev/null 2>&1

    cp --dereference /etc/resolv.conf ${MNT}/etc/ > /dev/null 2>&1

    mount --types proc /proc ${MNT}/proc > /dev/null 2>&1
    mount --rbind /sys ${MNT}/sys > /dev/null 2>&1
    mount --make-rslave ${MNT}/sys > /dev/null 2>&1
    mount --rbind /dev ${MNT}/dev > /dev/null 2>&1
    mount --make-rslave ${MNT}/dev > /dev/null 2>&1
    mount --bind /run ${MNT}/run > /dev/null 2>&1
    mount --make-slave ${MNT}/run> /dev/null 2>&1 

    printf "✅ Extracted the base fs into ${MNT}!\n\n"

    chroot ${MNT} /bin/bash -c "./chroot.sh" 

    return 0
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