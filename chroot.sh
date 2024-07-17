#!/bin/bash

printf "✅ Dropped into chroot!\n\n"

# gum bin loc
GUM_CMD=./gum

# Mounting sub-volumes
function mnt_subs() {

    mkdir /.snapshots/ > /dev/null 2>&1

    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@snapshots /dev/nvme0n1p3 /.snapshots > /dev/null 2>&1
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@home /dev/nvme0n1p3 /home > /dev/null 2>&1
    
    printf "✅ Mounted sub volumes!\n\n"

    return 0
}

# Setting locale
function locale_gen() {

    cat > /etc/locale.gen <<EOF
# Whatever else?
en_US.UTF-8 UTF-8
EOF
    locale-gen > /dev/null 2>&1

    printf "✅ locale.gen was modified!\n\n"

    return 0
}

#
#  Portage stuff
#

# Sync with git instead
function git_sync() {

    $GUM_CMD spin --spinner line --title "running \`emerge-webrsync\`..." -- \
        emerge-webrsync 

    $GUM_CMD spin --spinner line --title "running \`emerge --sync\`..." -- \
        emerge --sync
    
    $GUM_CMD spin --spinner line --title "running \`emerge dev-vcs/git app-eselect/eselect-repository\`..." -- \
        emerge dev-vcs/git app-eselect/eselect-repository

    eselect repository enable gentoo > /dev/null 2>&1
    eselect repository enable guru > /dev/null 2>&1

    $GUM_CMD spin --spinner line --title "running \`rm -r /var/db/repos/gentoo\`..." -- \
        rm -r /var/db/repos/gentoo

    $GUM_CMD spin --spinner line --title "running \`emaint sync\`..." -- \
        emaint sync
    
    printf "✅ Syncing portage with git!\n\n"

    return 0
}

# Establish proper vals
function cpu_flags() {

    $GUM_CMD spin --spinner line --title "running \`emerge --oneshot app-portage/cpuid2cpuflags\`..." -- \
        emerge --oneshot app-portage/cpuid2cpuflags > /dev/null 2>&1

    CPU_FLAGS=$(cpuid2cpuflags | cut -d: -f2-)

    MAKEOPTS_DEFAULT="-j12 -l12"
    EMERGE_OPTS="--jobs=12 --load-average=12"

    #

    $GUM_CMD spin --spinner line --title "running \`emerge --oneshot resolve-march-native\`..." -- \
        emerge --oneshot resolve-march-native > /dev/null 2>&1

    MARCH=$(resolve-march-native)

    COMMON_FLAGS="${MARCH} -O2 -pipe"

    return 0
}

#

function gpu_check() {

    GPU_VAL=$($GUM_CMD choose --limit 1 --header "GPU?" "amd" "nvidia" "intel")
    if [[ -z "$GPU_VAL" ]]; then
        printf "\n❌ No GPU was selected...\n\nTry again?\n\n"
        return 1
    fi

    return 0
}

function kb_check() {

    $GUM_CMD confirm "Are you on a laptop?" && KB_VAL="synaptics libinput" || KB_VAL="libinput"

    return 0
}

# Generate MAKEOPTS...
function gen_makeopts() {
    nproc_threads=$(nproc)
    ram_gb=$(grep MemTotal /proc/meminfo | awk '{print $2 / 1024}')

    makeopts=$(echo "min($ram_gb/2, $nproc_threads)" | bc -l)

    # makeopts="-j${nproc_threads} -l$(bc -l <<< "scale=0; ${nproc_threads} * 1.25")"

    echo "$makeopts"
}

# Select option for MAKEOPTS
function sel_makeopts() {
     if $GUM_CMD confirm "Would you like to specifiy your MAKEOPTS?"; then

        MAKEOPTS=$($GUM_CMD input --width 120 \
            --value "-j6 -l6" \
            --prompt "👉 Input your MAKEOPTS: " | head -n 1)
        if [[ -z "$MAKEOPTS" ]]; then
            printf "\n❌ No valid block device was selected...\n\nTry again?\n\n"
            return 1
        else 
            if ! gen_makeopts; then
                exit 1
            fi
            return 1
        fi
    else
        if ! gen_makeopts; then
            exit 1
        fi
        return 1
    fi
}

# Generate make.conf...
function mk_conf() {

    if ! sel_makeopts; then
        exit 1
    fi

    if ! gpu_check; then
        exit 1
    fi

    if ! kb_check; then
        exit 1
    fi

    cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${COMMON_FLAGS}"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

CPU_FLAGS_X86="${CPU_FLAGS}"

MAKEOPTS="${MAKEOPTS_DEFAULT}"
PORTAGE_NICENESS="1"

EMERGE_DEFAULT_OPTS="--ask --tree --verbose ${EMERGE_OPTS} --with-bdeps y --complete-graph y"
FEATURES="candy fixlafiles unmerge-orphans parallel-fetch parallel-install"

ACCEPT_LICENSE="*"
ACCEPT_KEYWORDS="~amd64"
GRUB_PLATFORMS="efi-64"
VIDEO_CARDS="${GPU_VAL}"
INPUT_DEVICES="${KB_VAL}"

PORTAGE_TMPDIR="/var/tmp/portage"
PORTAGE_SCHEDULING_POLICY="idle"

LC_MESSAGES="C"
LANG="en_US.UTF-8"
L10N="en en-US"
EOF
    printf "✅ make.conf was generated!\n\n"

    return 0
}

#

function base_flags() {

    cat > /etc/portage/package.use/\* <<EOF
#################################### GL0BAL ####################################
#
# Enabled
#
*/* minimal dist-kernel elogind dbus udev udisks python_targets_python3_12
*/* bash-completion jpeg jpegxl heif gif png opengl nvenc vaapi vulkan
*/* pulseaudio wayland X
#
# Disabled
#
*/* -python_targets_python2_7 -systemd -ipv6 -nouveau -kde -gnome -consolekit
*/* -cups -crypt
#################################### L0CAL #####################################
EOF
    printf "✅ USE flags were set!\n\n"

    return 0
}



function portage() {

    if ! git_sync; then
        exit 1
    fi
        
    if ! cpu_flags; then
        exit 1
    fi
    
    if ! mk_conf; then
        exit 1
    fi

    if ! base_flags; then
        exit 1
    fi
    
    return 0
}

#
#  Kernel stuff
#

function kern_flags() {

    cat > /etc/portage/package.use/installkernel <<EOF
sys-kernel/installkernel dracut grub
EOF
    printf "✅ USE flags for our kernel were set!\n\n"

    return 0
}

function kernel() {

    if ! kern_flags; then
        exit 1
    fi

    $GUM_CMD spin --spinner line --title "running \`emerge sys-kernel/linux-firmware\`..." -- \
        emerge sys-kernel/linux-firmware > /dev/null 2>&1

    
    return 0
}

#
#  Heart of this script
#

function chroot() {

    clear

    if ! gen_makeopts; then 
        exit 1
    fi 

    # if ! mnt_subs; then
    #     exit 1
    # fi

    # if ! locale_gen; then
    #     exit 1
    # fi

    # if ! portage; then
    #     exit 1
    # fi
    
    # if ! kernel; then
    #     exit 1
    # fi
}

chroot

