#!/bin/bash

echo "ECHO FROM CHROOT"

#
# Formatting
#

function make_conf() {
    
    COMMON_FLAGS="-march=alderlake -mabm -mno-cldemote -mno-kl -mno-sgx -mno-widekl -mshstk --param=l1-cache-line-size=64 --param=l1-cache-size=48 -O2 -pipe"

    MAKEOPTS="-j12 -l12"
    PORTAGE_NICENESS="1"

    # Set variables for Gentoo settings
    GENTOO_MIRRORS="https://mirrors.mit.edu/gentoo-distfiles/"
    PORTDIR="/var/db/repos/gentoo"
    DISTDIR="/var/cache/binpkgs"
    PKGDIR="/var/cache/binpkgs"

    # Set language settings
    LC_MESSAGES=C
    LANG="en_US.UTF-8"
    L10N="en en-US"

    # Generate the make.conf file
    cat > /etc/portage/make.conf <<EOF
    # These settings were set by the catalyst build script that automatically
    # built this stage.
    # Please consult /usr/share/portage/config/make.conf.example for a more
    # detailed example.

    COMMON_FLAGS="${COMMON_FLAGS}"
    CFLAGS="${COMMON_FLAGS}"
    CXXFLAGS="${COMMON_FLAGS}"
    FCFLAGS="${COMMON_FLAGS}"
    FFLAGS="${COMMON_FLAGS}"

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
}

if ! make_conf; then
    exit 1
fi
