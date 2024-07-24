#!/bin/bash

GUM_CMD=./gum

function init() {

    clear # the screen...

    printf "\n✅ dropped into chroot\n\n"

    # 

    return 0
}

# 

# Mounting sub-volumes.
function mnt_subs() {

    mkdir /.snapshots/ &> /dev/null

    # Mount the `@home` and `@snapshots` sub-volumes.
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@snapshots /dev/nvme0n1p3 /.snapshots &> /dev/null
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@home /dev/nvme0n1p3 /home &> /dev/null
    
    printf "✅ mounted sub-volumes\n\n"

    # 

    return 0
}

# 

function add_netmgr() {

    # Confirm whether or not to install and enable `networkmanager`
    if $GUM_CMD confirm "Do you want to install \`NetworkManager\`?"; then

        $GUM_CMD spin --spinner line --title "Emerging \`net-misc/dhcpcd\`..." -- \
            emerge net-misc/networkmanager

        rc-update add NetworkManager default &> /dev/null
        rc-service NetworkManager start &> /dev/null

        printf "✅ \`NetworkManager\` was installed & enabled\n\n"

    else 
        return 0
    fi
}

function set_net() {

    # Input hostname, or throw an error...
    HOST=$($GUM_CMD input --width 120 \
        --placeholder "gentwo" \
        --prompt "👉 Input your hostname: " | head -n 1)
        
    if [[ -z "$HOST" ]]; then

        printf "\n❌ Hostname wasn't defined...\n\nTry again?\n\n"

        return 1
    fi 

    echo ${HOST} > /etc/hostname &> /dev/null
    echo ${HOST} > /etc/conf.d/hostname &> /dev/null

    cat > /etc/locale.gen <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOST}.localdomain     ${HOST}
EOF

    printf "✅ hostname + hosts were set\n\n"

    # 

    $GUM_CMD spin --spinner line --title "Emerging \`net-misc/dhcpcd\`..." -- \
        emerge net-misc/dhcpcd

    rc-update add dhcpcd default &> /dev/null
    rc-service dhcpcd start &> /dev/null

    printf "✅ \`dhcpcd\` has been enabled\n\n"

    # 

    if ! add_netmgr; then
        exit 1
    fi

    # 

    return 0

}

# 

# Set the timezone.
function set_tz() {

    rm /etc/localtime &> /dev/null

    $GUM_CMD spin --spinner line --title "Emerging \`sys-libs/timezone-data\`..." -- \
        emerge --oneshot sys-libs/timezone-data

    # 

    # Input tz, or throw an error...
    TZ=$($GUM_CMD input --width 120 \
        --placeholder "Country/City" \
        --prompt "👉 Input your timezone: " | head -n 1)
        
    if [[ -z "$TZ" ]]; then

        printf "\n❌ Timezone wasn't defined...\n\nTry again?\n\n"

        return 1
    fi 

    echo "${TZ}" > /etc/timezone &> /dev/null

    emerge --config sys-libs/timezone-data &> /dev/null

    # 

    # $GUM_CMD spin --spinner line --title "Emerging \`net-misc/ntp\`..." -- \
    #     emerge net-misc/ntp

    # 

    return 0
}

# Setting locale
function locale_gen() {

    cat > /etc/locale.gen <<EOF
# Whatever else?
en_US.UTF-8 UTF-8
EOF
    locale-gen &> /dev/null

    eselect locale set en_US.utf8 &> /dev/null

    env-update &> /dev/null

    source /etc/profile &> /dev/null

    printf "✅ locale has been set\n\n"

    # 

    return 0
}

#
#  Portage stuff
#

# Sync with git instead
function git_sync() {

    $GUM_CMD spin --spinner line --title "Running \`emerge-webrsync\`..." -- emerge-webrsync 

    $GUM_CMD spin --spinner line --title "Running \`emerge --sync\`..." -- emerge --sync

    # 
    
    $GUM_CMD spin --spinner line --title "Emerging \`git\` & \`eselect-repository\`..." -- \
        emerge dev-vcs/git app-eselect/eselect-repository

    eselect repository disable gentoo &> /dev/null
    eselect repository enable gentoo &> /dev/null
    eselect repository enable guru &> /dev/null

    $GUM_CMD spin --spinner line --title "Running \`rm -r /var/db/repos/gentoo\`..." -- \
        rm -r /var/db/repos/gentoo

    $GUM_CMD spin --spinner line --title "Running \`emaint sync\`..." -- \
        emaint sync
    
    printf "✅ syncing portage with git\n\n"

    # 

    return 0
}

# Establish proper values.
function cpu_flags() {

    # Determine which CPU we're rockin.
    local vendor=$(cat /proc/cpuinfo | 
        (read -r _ && read id && echo "$id" | awk -F': ' '{print $2}'))
    
    if [ "$vendor" == "GenuineIntel" ] || [ "$vendor" == "AuthenticAMD" ]; then
      if [ "$vendor" == "GenuineIntel" ]; then
        CPU="intel"
      elif [ "$vendor" == "AuthenticAMD" ]; then
        CPU="amd"
      fi
    else
      echo "Err processing the vendor of the CPU..."
      return 1
    fi

    # 

    if [[ $CPU == "intel" ]]; then

        $GUM_CMD spin --spinner line --title "Emerging \`sys-firmware/intel-microcode\`..." -- \
            emerge sys-firmware/intel-microcode

        SIG=$(iucode_tool -S 2>&1 | grep -o "0.*$")
    fi 

    # 

    $GUM_CMD spin --spinner line --title "Emerging \`app-portage/cpuid2cpuflags\`..." -- \
        emerge --oneshot app-portage/cpuid2cpuflags

    CPU_FLAGS=$(cpuid2cpuflags | cut -d: -f2-)

    #

    $GUM_CMD spin --spinner line --title "Emerging \`resolve-march-native\`..." -- \
        emerge --oneshot resolve-march-native
    
    MARCH=$(resolve-march-native)

    COMMON_FLAGS="${MARCH} -O2 -pipe"

    # 
    
    return 0
}

#

# Obtain input for a GPU.
function gpu_check() {

    GPU=$($GUM_CMD choose --limit 1 --header "GPU?" "amd" "nvidia" "intel")

    if [[ -z "$GPU" ]]; then
        printf "\n❌ No GPU was selected...\n\nTry again?\n\n"
        return 1
    fi

    # 

    return 0
}

# 

# Obtain input for a Trackpad.
function kb_check() {

    $GUM_CMD confirm "Do you have a trackpad?" && KB="synaptics libinput" || KB="libinput"

    # 

    return 0
}

# 

# Generate MAKEOPTS...
function gen_makeopts() {

    local thread_cnt=$(nproc)
    local jobs=$((thread_cnt - 3))

    MAKEOPTS="-j$jobs -l12"
    EMERGE_OPTS="--jobs=$jobs --load-average=12"

    # 

    return 0
}

# 

# Select option for MAKEOPTS
function sel_makeopts() {
    
     if $GUM_CMD confirm "Would you like to specify your MAKEOPTS?"; then

        MAKEOPTS=$($GUM_CMD input --width 120 \
            --value "-j6 -l6" \
            --prompt "👉 Input your MAKEOPTS: " | head -n 1)

        if [[ -z "$MAKEOPTS" ]]; then

            printf "\n❌ This value should not be empty.\n\nTry again?\n\n"

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

# 

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

MICROCODE_SIGNATURES="${SIG}"

MAKEOPTS="${MAKEOPTS}"
PORTAGE_NICENESS="1"
PORTAGE_SCHEDULING_POLICY="idle"
PORTAGE_TMPDIR="/var/tmp/portage"
EMERGE_DEFAULT_OPTS="--ask --tree --verbose ${EMERGE_OPTS} --with-bdeps y --complete-graph y"
FEATURES="candy fixlafiles unmerge-orphans parallel-fetch parallel-install"

ACCEPT_LICENSE="*"
ACCEPT_KEYWORDS="~amd64"
GRUB_PLATFORMS="efi-64"
VIDEO_CARDS="${GPU}"
INPUT_DEVICES="${KB}"

LC_MESSAGES="C"
LANG="en_US.UTF-8"
L10N="en en-US"

GENTOO_MIRRORS="https://mirrors.mit.edu/gentoo-distfiles/"
EOF
    printf "✅ make.conf was generated\n\n"

    # 

    return 0
}

#

function base_flags() {

    cat > /etc/portage/package.use/\* <<EOF
#################################### GL0BAL ####################################
#
# Enabled
#
*/* minimal elogind dbus udev icu gtk qt5 qt6 bash-completion
*/* python_targets_python3_11 python_targets_python3_12
*/* jpeg jpegxl heif gif png opengl opencl nvenc vaapi vulkan
*/* pulseaudio pipewire gstreamer screencast wayland X
#
# Disabled
#
*/* -python_targets_python2_7 -systemd -ipv6 -nouveau -kde -gnome -consolekit
*/* -cups -crypt
#################################### L0CAL #####################################
EOF
    printf "✅ global and local USE flags\n\n"

    # 

    return 0
}

# 

function kern_flags() {

    cat > /etc/portage/package.use/installkernel <<EOF
sys-kernel/installkernel dracut grub
EOF

    printf "✅ dist-kernel USE flags\n\n"

    # 

    return 0
}

# 

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

    if ! kern_flags; then
        exit 1
    fi

    # 
    
    return 0
}

# 

function sys_inst() {
    
    $GUM_CMD spin --spinner line --title "Updating the @world set..." -- \
        emerge --ask --verbose --update --deep --newuse @world

    # $GUM_CMD spin --spinner line --title "installing the base system... p3" -- \
    #     emerge --depclean

    # $GUM_CMD spin --spinner line --title "installing the base system... p2" -- \
    #     emerge @preserved-rebuild

    printf "✅ installed the base system\n\n"

    #  

    return 0
}

# 

function kernel() {

    $GUM_CMD spin --spinner line --title "Emerging \`media-libs/freetype\`..." -- \
        emerge --oneshot freetype

    $GUM_CMD spin --spinner line --title "Emerging \`sys-kernel/gentoo-kernel-bin\`..." -- \
        emerge sys-kernel/gentoo-kernel-bin

    $GUM_CMD spin --spinner line --title "Emerging \`sys-kernel/linux-firmware\`..." -- \
        emerge sys-kernel/linux-firmware

    emerge --config sys-kernel/gentoo-kernel-bin

    # 

    return 0
}

# 

function root_pw() {

    # Input PW pt1, or throw an error...
    PW=$($GUM_CMD input --width 120 \
        --placeholder "gentwo" \
        --prompt "👉 Input the new root password: " | head -n 1)

    if [[ -z "$PW" ]]; then

        printf "❌ Cannot have an empty password...\n\nTry again?\n\n"

        return 1
    fi 

    # Input PW pt2, or throw an error...
    CONF=$($GUM_CMD input --width 120 \
        --placeholder "gentwo" \
        --prompt "👉 Input the new root password (again): " | head -n 1)

    if [[ -z "$CONF" ]]; then

        printf "❌ Cannot have an empty password...\n\nTry again?\n\n"

        return 1
    fi 

    if [ "$PW" = "$CONF" ]; then

        echo -e "${PW}\n${CONF}" | passwd &> /dev/null

        if [ $? -eq 0 ]; then

            printf "✅ root pw was set\n\n"
            return 0
        else

            printf "❌ Failed to set the root pw..\n\nTry again?\n\n"

            if ! set_pw; then
                exit 1
            fi

            return 0
        fi
    else

        printf "❌ Passwords did not match...\n\nTry again?\n\n"

        if ! set_pw; then
            exit 1
        fi

        return 0
    fi

    # 

}

function basics() {

    $GUM_CMD spin --spinner line --title "Emerging \`sys-fs/btrfs-progs\`..." -- \
        emerge sys-fs/btrfs-progs

    $GUM_CMD spin --spinner line --title "Emerging \`sys-apps/nvme-cli\`..." -- \
        emerge sys-apps/nvme-cli

    $GUM_CMD spin --spinner line --title "Emerging \`sys-apps/biosdevname\`..." -- \
        emerge sys-apps/biosdevname

    $GUM_CMD spin --spinner line --title "Emerging \`sys-apps/mlocate\`..." -- \
        emerge sys-apps/mlocate

    $GUM_CMD spin --spinner line --title "Emerging \`app-shells/bash-completion\`..." -- \
        emerge app-shells/bash-completion

    $GUM_CMD spin --spinner line --title "Emerging \`sys-block/io-scheduler-udev-rules\`..." -- \
        emerge sys-block/io-scheduler-udev-rules

    $GUM_CMD spin --spinner line --title "Emerging \`app-admin/sysklogd\`..." -- \
        emerge app-admin/sysklogd

    # 

    rc-update add sysklogd default &> /dev/null
    rc-service sysklogd start &> /dev/null

    rc-update add elogind default &> /dev/null
    rc-service elogind start &> /dev/null

    # 

    return 0
}

# 

function grub() {

    $GUM_CMD spin --spinner line --title "Emerging \`sys-boot/grub\`..." -- \
        emerge sys-boot/grub 

    # $GUM_CMD spin --spinner line --title "Emerging \`sys-boot/efibootmgr\`..." -- \
    #     emerge sys-boot/efibootmgr

    $GUM_CMD spin --spinner line --title "Running \`grub-install\`..." -- \
        grub-install --efi-directory=/boot/efi

    grub-mkconfig -o /boot/grub/grub.cfg &> /dev/null

    emerge --config sys-kernel/gentoo-kernel-bin &> /dev/null

    # 

    return 0
}

# 

function doas() {

    $GUM_CMD spin --spinner line --title "Emerging \`app-admin/doas\`..." -- \
        emerge app-admin/doas

    touch /etc/doas.conf &> /dev/null
    chown -c root:root /etc/doas.conf &> /dev/null
    chmod -c 0400 /etc/doas.conf &> /dev/null

    cat > /etc/doas.conf <<EOF
permit persist :wheel
EOF

    # 

    return 0
}

# 

function new_usr() {

    local username=$($GUM_CMD input --width 120 \
        --placeholder "anon" \
        --prompt "👉 Input your username: " | head -n 1)

    if [[ -z "$USERNAME" ]]; then

        printf "❌ Cannot have an empty username...\n\nTry again?\n\n"

        return 1
    fi 

    useradd -m -G users,wheel,audio,cdrom,portage,usb,input,video -s /bin/bash ${username} &> /dev/null

    # 

    PW=$($GUM_CMD input --width 120 \
        --placeholder "PkxgbEM%@hdBnub4T" \
        --prompt "👉 Input the new root password: " | head -n 1)

    if [[ -z "$PW1" ]]; then

        printf "❌ Cannot have an empty password...\n\nTry again?\n\n"

        return 1
    fi 

    # 

    CONF=$($GUM_CMD input --width 120 \
        --placeholder "PkxgbEM%@hdBnub4T " \
        --prompt "👉 Input the new root password (again): " | head -n 1)

    if [[ -z "$CONF" ]]; then

        printf "❌ Cannot have an empty password...\n\nTry again?\n\n"

        return 1
    fi 

    # 

    if [ "$PW" = "$CONF" ]; then

        echo -e "${PW}\n${CONF}" | passwd ${username} &> /dev/null

        if [ $? -eq 0 ]; then

            printf "✅ pw for ${username} was set\n\n"
            return 0
        else

            printf "❌ Failed to set the root pw..\n\nTry again?\n\n"

            if ! set_pw; then
                exit 1
            fi

            return 0
        fi
    else

        printf "❌ Passwords did not match...\n\nTry again?\n\n"

        if ! set_pw; then
            exit 1
        fi

        return 0
    fi

    # 

    return 0
}

# 

function font_conf() {

    $GUM_CMD spin --spinner line --title "Emerging \`noto\` & \`noto-emoji\`..." -- \
        media-fonts/noto media-fonts/noto-emoji

    $GUM_CMD spin --spinner line --title "Emerging \`fonts-meta\` & \`symbola\`..." -- \
        media-fonts/fonts-meta media-fonts/symbola

    $GUM_CMD spin --spinner line --title "Emerging \`corefonts\`..." -- \
        media-fonts/corefonts

    # 

    eselect fontconfig disable 10-hinting-slight.conf &> /dev/null
    eselect fontconfig disable 10-no-antialias.conf &> /dev/null
    eselect fontconfig disable 10-sub-pixel-none.conf &> /dev/null
    eselect fontconfig enable 10-hinting-full.conf &> /dev/null
    eselect fontconfig enable 10-sub-pixel-rgb.conf &> /dev/null
    eselect fontconfig enable 10-yes-antialias.conf &> /dev/null
    eselect fontconfig enable 11-lcdfilter-default.conf &> /dev/null
    eselect fontconfig enable 10-powerline-symbols.conf &> /dev/null
    eselect fontconfig enable urw-standard-symbols-ps.conf &> /dev/null
    eselect fontconfig enable 66-noto-sans.conf &> /dev/null
    eselect fontconfig enable 66-noto-serif.conf &> /dev/null
    eselect fontconfig enable 75-noto-emoji-fallback.conf &> /dev/null
    eselect fontconfig enable 80-delicious.conf &> /dev/null

    return 0
}

#
#  Heart of this script
#

function chroot() {

    if ! init; then
        exit 1
    fi

    if ! mnt_subs; then
        exit 1
    fi

    if ! set_net; then
        exit 1
    fi

    if ! set_tz; then
        exit 1
    fi

    if ! locale_gen; then
        exit 1
    fi

    if ! portage; then
        exit 1
    fi

    if ! sys_inst; then
        exit 1
    fi
    
    if ! kernel; then
        exit 1
    fi

    if ! root_pw; then
        exit 1
    fi

    if ! basics; then
        exit 1
    fi

    if ! grub; then
        exit 1
    fi

    if ! doas; then
        exit 1
    fi

    if ! new_usr; then
        exit 1
    fi

    if ! font_conf; then
        exit 1
    fi

    # # 

    rm -rf /var/tmp/portage/* &> /dev/null
    rm -rf /var/cache/distfiles/* &> /dev/null
    rm -rf /var/cache/binpkgs/* &> /dev/null

    return 0
}

if ! chroot; then
    exit 1
fi

exit 0
