#!/usr/bin/env bash
#
# 00-host-prep.sh
#
# Checks whether this host is ready to build LFS: required tools,
# minimum versions, and disk/RAM headroom for the build itself.
# (Building LFS needs more resources than the target system will —
# a 512MB target doesn't mean you can build on 512MB.)
#
# Usage: ./00-host-prep.sh
#
set -uo pipefail

PASS=0
FAIL=0

check_version() {
    local name="$1" cmd="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[MISSING] $name — not found"
        FAIL=$((FAIL+1))
        return
    fi
    echo "[FOUND]   $name — $($cmd --version 2>&1 | head -n1)"
    PASS=$((PASS+1))
}

echo "== Required build tools =="
check_version "Bash"        bash
check_version "Binutils"    ld
check_version "Bison"       bison
check_version "Coreutils"   sort
check_version "Diffutils"   diff
check_version "Findutils"   find
check_version "Gawk"        gawk
check_version "GCC"         gcc
check_version "G++"         g++
check_version "C library"   ldd
check_version "Grep"        grep
check_version "Gzip"        gzip
check_version "M4"          m4
check_version "Make"        make
check_version "Patch"       patch
check_version "Perl"        perl
check_version "Python3"     python3
check_version "Sed"         sed
check_version "Tar"         tar
check_version "Texinfo"     makeinfo
check_version "Xz"          xz

echo
echo "== FeatherOS packaging tools (Alpine host) =="
check_version "apk"         apk
check_version "abuild"      abuild

echo
echo "== Disk / RAM check =="

ROOT_AVAIL_GB=$(df -BG --output=avail / | tail -n1 | tr -dc '0-9')
MEM_TOTAL_MB=$(free -m | awk '/^Mem:/{print $2}')

echo "Available disk on /: ${ROOT_AVAIL_GB:-unknown} GB (recommend 30GB+ free for a full LFS build)"
echo "Host RAM: ${MEM_TOTAL_MB:-unknown} MB (recommend 4GB+ to build comfortably; less is possible but slow and swap-heavy)"

if [ -n "${ROOT_AVAIL_GB:-}" ] && [ "$ROOT_AVAIL_GB" -lt 30 ]; then
    echo "[WARN] Less than 30GB free — LFS source + build artifacts can get large, especially building GCC/kernel twice."
fi

echo
echo "== Summary =="
echo "Tools found: $PASS, missing: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "Install the missing tools above before starting Stage 1."
    echo "On an Alpine build host: apk add build-base abuild git curl"
    echo "(other hosts: use that distro's package manager, e.g. apt/dnf)."
    exit 1
else
    echo "Host looks ready for Stage 1 (toolchain build)."
fi
