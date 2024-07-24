#!/bin/bash

GUM_CMD=gum

# Install dependencies...
function get_deps() {
    # Check if we're using an Arch-based distro:
    if command -v pacman &> /dev/null; then
        # Check if we have jq installed...
        if ! pacman -Qs jq &> /dev/null; then
            printf "\n📦 installing the pkg \`jq\`...\n"
            pacman -Sy --noconfirm jq  &> /dev/null
            printf "\n✅ successfully installed \`jq\`\n"
        fi
    fi

    # 

    # Ensure `gum` is present...
    if ! set_gum; then
        exit 1
    fi

    # 
    
    return 0 
}

# Fetch gum bin...
function get_gum() {

    # Capture the file name, of the latest version found. It will be named exactly as it was uploaded.
    local file_name=$(jq -r '.[0].assets[] | select(.name | test("gum_.*_Linux_x86_64.tar.gz")) .name' ${CACHED_GUM} | 
        head -n 1)
    # Capture the url to download the latest version of the pre-built gum binary.
    local dl_url=$(jq -r '.[0].assets[] | select(.name | test("gum_.*_Linux_x86_64.tar.gz")) .browser_download_url' ${CACHED_GUM} | 
        head -n 1)
    
    # File & extracted directory name.
    local ext_dir=${file_name%.tar.gz}
    # Simplify the directory name:
    local new_dir=./cache/gum_${LATEST_GUM}

    # Ensure the new dir is created.
    mkdir -p $new_dir &> /dev/null

    # 

    # Download the latest pre-built gum binary, named as it was uploaded.
    curl -L ${dl_url} -o ./cache/${file_name} &> /dev/null
    # Extract the downloaded tarball as a directory.
    tar -xf ./cache/${file_name} -C ./cache/ &> /dev/null
    # Copy the bin into the newly created directory.
    mv ./cache/${ext_dir}/gum $new_dir &> /dev/null
    # Remove whatever resides, afterwards.
    rm -rf ./cache/${ext_dir} &> /dev/null
    rm ./cache/${file_name} &> /dev/null

    # 

    return 0 
}

# Establish bin loc...
function set_gum() {

    local gum_url="https://api.github.com/repos/charmbracelet/gum/releases"
    CACHED_GUM="./cache/gum_releases.json"

    # Check if it's the first run:
    if ! test -f "$CACHED_GUM"; then
        # It is? Download a page that lists the latest releases.
        curl -sS ${gum_url} > ${CACHED_GUM}
        # Capture the name of the latest version.
        local cached_ver=$(jq -r '.[] | .name' ${CACHED_GUM} | head -n 1)
        # Since we've just downloaded the file...
        LATEST_GUM=${cached_ver}
    else 
        # Capture the name of the version that was cached.
        local cached_ver=$(jq -r '.[] | .name' ${CACHED_GUM} | head -n 1)
        # Check if that matches the latest version found.
        latest_ver=$(curl -sS ${gum_url} | jq -r '.[] | .name' | head -n 1)
    fi

    # With the file name, pre-establish the location for our gum binary.
    GUM_BIN=./cache/gum_${LATEST_GUM}/gum

    # Either reran or the first run...
    if [ $cached_ver == $LATEST_GUM ]; then
        # Check if we have the bin...
        if ! test -f ${GUM_BIN}; then 
            if ! get_gum; then
                return 1
            fi
        fi
    else
        # Versioning difference detected, rm and update...
        printf "\n👀 New \`gum\` release detected. Updating...\n\n"
        rm -rf ./cache/gum_${cached_ver} > /dev/null 2>&1
        curl -sS ${repo_url} > ${CACHED_GUM} > /dev/null 2>&1
        if ! get_gum; then
            return 1
        fi
    fi

    # Set gum bin loc
    GUM_CMD=${GUM_BIN}

    # 
    
    return 0 
}

# Initialization
function init() {

    clear # the screen...

    # Ensure privs are met...
    if [ $(id -u) != 0 ]; then
        printf "\n❌ Script not ran as root. Exiting.\n\n"
        return 1
    fi

    # Ensure a valid network connection...
    if ! ping -c 1 -w 2 google.com &> /dev/null; then
        printf "\n❌ No internet connection. Exiting.\n\n"
        return 1
    fi

    # Ensure this dir exists...
    mkdir -p ./cache

    # Ensure dependencies are installed...
    if ! get_deps; then
        return 1
    fi

    # 
    
    return 0 
}

#
# Block Selection
#

function sel_block() {

    clear # the screen...

    # List the different blocks found connected to the system.
    local blks=$(lsblk -d -n -oNAME,RO | grep '0$' | awk {'print $1'})
    # Choose one block from the list, to install Gentoo Linux on.
    local block=$($GUM_CMD choose --limit 1 --header "Device block to partition:" <<< "$blks")
    if [[ -z "$block" ]]; then
        # Probably interrupted...
        printf "\n❌ No valid block device was selected?\n\nTry again?\n\n"
        return 1
    fi

    # Location for the block device.
    BLK_LOC=$"/dev/$block"

    # Confirm whether or not the selected block is correct.
    if $GUM_CMD confirm "So, we're installing Gentoo on $BLK_LOC?"; then
        # If a selection was made, go ahead and continue.
        printf "\n⌛ time to partition $BLK_LOC...\n\n"
    else # Rerun the selection...
        if ! sel_block; then
            return 1
        fi
    fi

    # 

    return 0 
}

#
# Partitioning
#

function input_boot_size() {

    # Input the size, or throw an error...
    BOOT_SIZE=$($GUM_CMD input --width 120 \
        --value 120 \
        --prompt "👉 Input the size (in MB), for your BOOT partition: " | head -n 1)

    if [[ -z "$BOOT_SIZE" ]]; then
        printf "\n❌ x...\n\n"
        return 1
    fi

    # 
    
    return 0 
}

function input_swap_size() {

    # Input the size, or throw an error...
    SWAP_SIZE=$($GUM_CMD input --width 120 \
        --value 32000 \
        --prompt "👉 Input the size (in MB), for your SWAP partition: " | head -n 1)

    if [[ -z "$SWAP_SIZE" ]]; then
        printf "\n❌ x...\n\n"
        return 1
    fi

    # 
    
    return 0 
}

function part_block() {

    # Obtain the `BOOT_SIZE`
    if ! input_boot_size; then
        return 1
    fi

    # Obtain the `SWAP_SIZE`
    if ! input_swap_size; then
        return 1
    fi

    # Calculate the correct sectors
    local boot_sec=$(($BOOT_SIZE * 1048576 / 512))
    local swap_sec=$(($SWAP_SIZE * 1048576 / 512))
    local root_sec=$(($boot_sec + $swap_sec + 4098))

    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${BLK_LOC} &> /dev/null
      g # new GPT
      n # new partition
      1 # default partition 1
        # default - start at beginning of disk
      +${BOOT_SIZE}M # MB BOOT partition
      n # new partition
      2 # default partition 2
        # default, start immediately after preceding partition
      +${SWAP_SIZE}M # MB SWAP partition
      t # set type
      2 # of part 2
      19 # swap type
      n # new partition
      3 # partition number 3
      $root_sec
        # default, extend partition to end of disk
      w # write the partition table
EOF

    printf "✅ BOOT, SWAP & ROOT partitions were created!\n\n"

    # 

    return 0 
}

#
# Formatting
#

function fmt_parts() {

    # TODO: Handle in sel_block()
    # Dynamically (diff disk types)
    BOOT=$(printf "%sp1" "$BLK_LOC")
    SWAP=$(printf "%sp2" "$BLK_LOC")
    ROOT=$(printf "%sp3" "$BLK_LOC")

    # 

    # Format the BOOT partition.
    mkfs.vfat -F 32 ${BOOT} &> /dev/null

    printf "✅ BOOT was formatted to Fat32\n\n"

    # 

    # Format the SWAP partition.
    mkswap ${SWAP} &> /dev/null

    printf "✅ SWAP was made\n\n"

    # 

    # Format the ROOT partition.
    mkfs.btrfs -f ${ROOT} &> /dev/null

    printf "✅ ROOT was formatted to BTRFS\n\n"

    # 

    return 0 
}

#
# Preparing Base FS
#

function cp_scripts() {
    
    # Copy over the chroot script + gum bin to ROOT.
    cp ./chroot.sh ${MNT} &> /dev/null
    cp ${GUM_BIN} ${MNT} &> /dev/null

    # Copy over the currently generated `resolv.conf` file.
    cp --dereference /etc/resolv.conf ${MNT}/etc/ &> /dev/null

    printf "✅ copied over the required assets\n\n"

    # 

    return 0 
}

#

function ext_base() {

    $GUM_CMD spin --spinner line --title "Extracting the base fs..." -- \
        tar xpvf ./cache/stage3-*.tar.xz -C "${MNT}" --xattrs-include='*.*' --numeric-owner 

    printf "✅ extracted the stage3 into ${MNT}\n\n"

    # 

    return 0 
}

# 

function get_base() {

    # Define the cached index page.
    local cached="./cache/stage3.html"
    
    # Construct the mirror where we'll retrieve the tarball.
    local params="amd64/autobuilds/current-stage3-amd64-openrc"
    local url="https://mirrors.mit.edu/gentoo-distfiles/releases/${params}/"

    # Curl the index page for the latest Stage3.
    curl -L ${url} -o ${cached} > /dev/null 2>&1

    # 

    # Capture most of the file name from the index gathered.
    local idx_name=$(grep -o '<a href="[^">]*"' ${cached} | cut -d'"' -f2- | grep '.tar.xz"')
    # Process the name of the latest file we're looking for...
    local base_name=${idx_name%\"}

    local base_loc="./cache/${base_name}"
    local full_url=${url}${base_name}

    # Use glob pattern to match files starting with "stage3-"
    local old_loc=$(find "./cache/" -maxdepth 1 -name stage3-*)
    local old_file=${old_loc#./cache/}

    # 

    # If we haven't ran this before...
    if test -z "$old_loc"; then

        # Curl the latest Gentoo AMD64 OpenRC Stage3 tarball.
        $GUM_CMD spin --spinner line --title "Downloading the base fs..." -- \
            curl -L ${full_url} -o ${base_loc}

        printf "✅ downloaded the latest stage3 tarball\n\n"

        # 

        return 0
    fi

    # 

    # Check if the last cached version matches:
    if ! [ $old_file == $base_name ]; then

        # Rm old file.
        rm ${old_loc}

        # Curl the latest Gentoo AMD64 OpenRC Stage3 tarball.
        $GUM_CMD spin --spinner line --title "Downloading the base fs..." -- \
            curl -L ${full_url} -o ${base_loc}

        printf "✅ downloaded the latest stage3 tarball\n\n"

        #

        return 0
    fi

    printf "✅ reusing our latest stage3 tarball\n\n"

    # 

    return 0 
}

#

function prep_base() {

    MNT=$"/mnt/gentoo"

    # Make and mount the base sys.
    mkdir -p ${MNT} &> /dev/null
    mount ${ROOT} ${MNT} &> /dev/null

    # 

    # Create the different sub-volumes desired. 
    btrfs subvolume create ${MNT}/@ &> /dev/null
    btrfs subvolume create ${MNT}/@home &> /dev/null
    btrfs subvolume create ${MNT}/@snapshots &> /dev/null

    # Unmount, for the next step.
    umount -l ${MNT} &> /dev/null

    printf "✅ sub-volumes were created\n\n"

    # 

    # Mount the root, `@` sub-volume.
    BTR_ROOT_OPTS="defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@"
    mount -t btrfs -o ${BTR_ROOT_OPTS} ${ROOT} ${MNT} &> /dev/null

    # 

    # Make and mount the BOOT partition.
    mkdir -p ${MNT}/boot/efi &> /dev/null
    mount ${BOOT} ${MNT}/boot/efi &> /dev/null

    # 

    # Enable the SWAP partition.
    swapon ${SWAP} &> /dev/null

    # 

    # Copy essentials over.
    if ! cp_scripts; then
        return 1
    fi

    # Gather Stage3 tarball.
    if ! get_base; then
        return 1
    fi

    # Extract the base FS.
    if ! ext_base; then
        return 1
    fi
    
    # 

    # Mounting all of the necessary filesystems.
    mount --types proc /proc ${MNT}/proc &> /dev/null
    mount --rbind /sys ${MNT}/sys &> /dev/null
    mount --make-rslave ${MNT}/sys &> /dev/null
    mount --rbind /dev ${MNT}/dev &> /dev/null
    mount --make-rslave ${MNT}/dev &> /dev/null
    mount --bind /run ${MNT}/run &> /dev/null
    mount --make-slave ${MNT}/run &> /dev/null
    
    chroot ${MNT} /bin/bash -c "./chroot.sh" 

    # 

    return 0 
}

# 

function gen_fstab() {

    local url="https://raw.githubusercontent.com/glacion/genfstab/master/genfstab"

    curl -o cache/genfstab $url

    cd cache 

    chmod -x genfstab

    ./genfstab "${MNT}" > "${MNT}"/etc/fstab

    printf "✅ fstab was generated\n\n"

    cd ../

    # 

    return 0
}

# 

function clean_up() {

    umount -l /mnt/gentoo/dev
    umount -R /mnt/gentoo

    # 

    return 0
}

#
#  Heart of this script
# 

function installer() {

    if ! init; then
        return 1
    fi

    if ! sel_block; then
        return 1
    fi

    if ! part_block; then
        return 1
    fi

    if ! fmt_parts; then
        return 1
    fi

    if ! prep_base; then
        return 1
    fi

    if ! gen_fstab; then
        return 1
    fi

    if ! clean_up; then
        return 1
    fi
}

if ! installer; then
    exit 1
fi

exit 0