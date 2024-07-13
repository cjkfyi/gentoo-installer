#!/bin/bash

printf "✅ Dropped into chroot!\n\n"

#
# Formatting
#

function mnt_subs() {
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@snapshots /dev/nvme0n1p3 /.snapshots
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@home /dev/nvme0n1p3 /home
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@devel /dev/nvme0n1p3 /devel
    mount -t btrfs -o defaults,noatime,compress=zstd,commit=120,autodefrag,ssd,space_cache=v2,subvol=@virt /dev/nvme0n1p3 /virt
    
    printf "✅ Mounted sub volumes!\n\n"
}

if ! mnt_subs; then
    exit 1
fi

#

function make_conf() {

    COMMON_FLAGS="-march=alderlake -mabm -mno-cldemote -mno-kl -mno-sgx -mno-widekl -mshstk --param=l1-cache-line-size=64 --param=l1-cache-size=48 -O2 -pipe"

    MAKEOPTS="-j12 -l12"
    PORTAGE_NICENESS="1"

    GENTOO_MIRRORS="https://mirrors.mit.edu/gentoo-distfiles/"
    PORTDIR="/var/db/repos/gentoo"
    DISTDIR="/var/cache/binpkgs"
    PKGDIR="/var/cache/binpkgs"

    LC_MESSAGES=C
    LANG="en_US.UTF-8"
    L10N="en en-US"

    cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${COMMON_FLAGS}"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="${MAKEOPTS}"
PORTAGE_NICENESS=${PORTAGE_NICENESS}

EMERGE_DEFAULT_OPTS="--ask --tree --verbose --jobs=12 --load-average=12 --with-bdeps y --complete-graph y"
FEATURES="candy fixlafiles unmerge-orphans parallel-fetch parallel-install"

CPU_FLAGS_X86="aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 ssse3 vpclmulqdq"

ACCEPT_LICENSE="*"
ACCEPT_KEYWORDS="~amd64"
GRUB_PLATFORMS="efi-64"
VIDEO_CARDS="nvidia"
INPUT_DEVICES="libinput"

PORTAGE_TMPDIR="/var/tmp/portage"
PORTAGE_SCHEDULING_POLICY="idle"

# NOTE: This stage was built with the bindist Use flag enabled

PORTDIR="${PORTDIR}"
DISTDIR="${DISTDIR}"
PKGDIR="${PKGDIR}"

# Set language of build output to English.
LC_MESSAGES=${LC_MESSAGES}
LANG=${LANG}
L10N=${L10N}

GENTOO_MIRRORS="${GENTOO_MIRRORS}"
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

function websync() {

    clear

    emerge-webrsync
    emerge --sync --quiet

    printf "✅ emerge-webrsync was ran!\n\n"
}

if ! websync; then
    exit 1
fi


