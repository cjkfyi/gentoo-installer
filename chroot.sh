#!/bin/bash

printf "✅ Dropped into chroot!\n\n"

#
# Formatting
#

function mnt_subs() {

    mkdir /.snapshots/

    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@snapshots /dev/nvme0n1p3 /.snapshots
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@home /dev/nvme0n1p3 /home
    
    printf "✅ Mounted sub volumes!\n\n"
}

if ! mnt_subs; then
    exit 1
fi

#

function testing() {

    cat > /etc/locale.gen <<EOF
# Whatever else?
en_US.UTF-8 UTF-8
EOF
    locale-gen

    printf "✅ locale.gen was modified!\n\n"
}

if ! testing; then
    exit 1
fi

#

function git_sync() {

    clear

    emerge-webrsync
    emerge --sync --quiet

    emerge --quiet dev-vcs/git
    emerge --quiet app-eselect/eselect-repository

    eselect repository disable gentoo
    eselect repository enable gentoo
    eselect repository enable guru

    rm -r /var/db/repos/gentoo

    emaint sync 

    printf "✅ Syncing portage with git!\n\n"
}


if ! git_sync; then
    exit 1
fi

#

function cpu_flags() {

    clear

    emerge --quiet --oneshot app-portage/cpuid2cpuflags 

    CPU_FLAGS=$(cpuid2cpuflags | cut -d: -f2-)

    MAKEOPTS="-j12 -l12"
    EMERGE_OPTS="--jobs=12 --load-average=12"

    #

    emerge --quiet --oneshot resolve-march-native

    MARCH=$(resolve-march-native)

    COMMON_FLAGS="${MARCH} -O2 -pipe"
}


if ! cpu_flags; then
    exit 1
fi

#

function make_conf() {

    cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${COMMON_FLAGS}"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

CPU_FLAGS_X86="${CPU_FLAGS}"

MAKEOPTS="${MAKEOPTS}"
PORTAGE_NICENESS="1"

EMERGE_DEFAULT_OPTS="--ask --tree --verbose ${EMERGE_OPTS} --with-bdeps y --complete-graph y"
FEATURES="candy fixlafiles unmerge-orphans parallel-fetch parallel-install"

ACCEPT_LICENSE="*"
ACCEPT_KEYWORDS="~amd64"
GRUB_PLATFORMS="efi-64"
VIDEO_CARDS="nvidia"
INPUT_DEVICES="libinput"

PORTAGE_TMPDIR="/var/tmp/portage"
PORTAGE_SCHEDULING_POLICY="idle"

PORTDIR="/var/db/repos/gentoo"
DISTDIR="/var/cache/binpkgs"
PKGDIR="/var/cache/binpkgs"

LC_MESSAGES="C"
LANG="en_US.UTF-8"
L10N="en en-US"
EOF
    printf "✅ make.conf was generated!\n\n"
}

if ! make_conf; then
    exit 1
fi

#

function use_flags() {

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
}

if ! use_flags; then
    exit 1
fi

#



