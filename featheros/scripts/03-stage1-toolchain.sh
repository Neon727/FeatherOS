#!/usr/bin/env bash
#
# 03-stage1-toolchain.sh
#
# Stage 1: builds an isolated FeatherOS toolchain (binutils, Linux
# headers, musl, GCC) into $LFS_ROOT/tools — independent of whatever
# exact package versions the Alpine build host happens to have, so
# later stages are reproducible.
#
# Simplification vs. classic (glibc) LFS: since the build host is
# Alpine (musl, x86_64) and the target is also musl x86_64, this is
# a native isolated build rather than a true cross-compile — no
# differing --target triple needed. If you later add a different
# target arch, this stage would need to become a real cross-build.
#
# Every step is checkpointed (see lib/checkpoint.sh) — safe to
# re-run after a failure or interruption; completed steps skip.
#
# Usage:
#   ./03-stage1-toolchain.sh              # run (or resume) the build
#   ./03-stage1-toolchain.sh --status     # show completed steps
#   ./03-stage1-toolchain.sh --reset      # clear all state, start over
#   ./03-stage1-toolchain.sh --reset gcc-build   # redo just one step
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"
SOURCES="$LFS_ROOT/sources"
TOOLS="$LFS_ROOT/tools"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

source "$SCRIPT_DIR/lib/checkpoint.sh"

# --- Pinned versions (checked current as of this writing — verify
# against upstream if it's been a while since this was written) ---
BINUTILS_VER="2.46.1"
GCC_VER="16.2.0"
MUSL_VER="1.2.6"
LINUX_VER="6.18"

BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VER}.tar.gz"
LINUX_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VER}.tar.xz"

# --- Handle CLI flags ---
case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

mkdir -p "$SOURCES" "$TOOLS"

# --- Helpers ---

# Tests whether an archive is actually complete/valid, not just
# present on disk. A file existing is NOT the same as a file being
# a good download — an interrupted transfer leaves a real file at a
# real path, just a truncated/corrupt one. This is what the bug fix
# actually checks before trusting any "already downloaded" file.
verify_archive_integrity() {
    local fname="$1"
    case "$fname" in
        *.tar.xz) xz -t "$fname" >/dev/null 2>&1 ;;
        *.tar.gz) gzip -t "$fname" >/dev/null 2>&1 ;;
        *) echo "  [WARN] don't know how to verify integrity of $fname — assuming OK" >&2; return 0 ;;
    esac
}

# --- Step functions ---

download_sources() {
    cd "$SOURCES" || return 1
    local checksum_file="$SOURCES/CHECKSUMS.sha256"
    touch "$checksum_file"

    for entry in \
        "binutils-${BINUTILS_VER}.tar.xz|$BINUTILS_URL" \
        "gcc-${GCC_VER}.tar.xz|$GCC_URL" \
        "musl-${MUSL_VER}.tar.gz|$MUSL_URL" \
        "linux-${LINUX_VER}.tar.xz|$LINUX_URL"
    do
        local fname="${entry%%|*}"
        local url="${entry##*|}"

        if [ -f "$fname" ]; then
            echo "  found existing file: $fname — verifying it's not a partial/corrupt download..."
            if ! verify_archive_integrity "$fname"; then
                echo "  $fname is corrupt or incomplete (likely an interrupted earlier download) — removing and re-fetching." >&2
                rm -f "$fname"
            fi
        fi

        if [ ! -f "$fname" ]; then
            echo "  downloading: $fname"
            curl -L --fail -o "$fname" "$url" || { echo "  download failed: $fname" >&2; return 1; }
            if ! verify_archive_integrity "$fname"; then
                echo "  freshly downloaded $fname still fails integrity check — download itself may be bad (bad mirror, flaky connection). Try again, or check your network." >&2
                return 1
            fi
        fi

        # First time we see this file, record its hash. If it's
        # already recorded, verify it matches — catches a corrupt
        # or partial re-download across a resumed build.
        local actual
        actual=$(sha256sum "$fname" | awk '{print $1}')
        if grep -q " $fname\$" "$checksum_file" 2>/dev/null; then
            local expected
            expected=$(grep " $fname\$" "$checksum_file" | awk '{print $1}')
            if [ "$actual" != "$expected" ]; then
                echo "  CHECKSUM MISMATCH for $fname — file may be corrupt. Delete it and re-run." >&2
                return 1
            fi
        else
            echo "$actual  $fname" >> "$checksum_file"
        fi
    done
}

extract_sources() {
    cd "$SOURCES" || return 1
    for tarball in binutils-*.tar.xz gcc-*.tar.xz musl-*.tar.gz linux-*.tar.xz; do
        [ -f "$tarball" ] || continue
        echo "  extracting: $tarball"
        tar xf "$tarball" || return 1
    done
}

build_binutils() {
    local src="$SOURCES/binutils-${BINUTILS_VER}"
    local build="$src/build"
    mkdir -p "$build" && cd "$build" || return 1
    "$src/configure" \
        --prefix="$TOOLS" \
        --disable-nls \
        --disable-werror \
        --with-sysroot="$TOOLS" || return 1
    make -j"$JOBS" || return 1
    make install || return 1
}

install_linux_headers() {
    local src="$SOURCES/linux-${LINUX_VER}"
    cd "$src" || return 1
    make mrproper || return 1
    make headers_install ARCH=x86_64 INSTALL_HDR_PATH="$TOOLS" || return 1
}

build_musl() {
    local src="$SOURCES/musl-${MUSL_VER}"
    cd "$src" || return 1
    ./configure --prefix="$TOOLS" || return 1
    make -j"$JOBS" || return 1
    make install || return 1
}

build_gcc() {
    local src="$SOURCES/gcc-${GCC_VER}"
    cd "$src" || return 1
    # Fetches gmp/mpfr/mpc into the gcc source tree so they build
    # alongside it — avoids depending on the host's versions of these.
    ./contrib/download_prerequisites || return 1
    mkdir -p build && cd build || return 1
    "$src/configure" \
        --prefix="$TOOLS" \
        --with-sysroot="$TOOLS" \
        --disable-multilib \
        --disable-nls \
        --enable-languages=c,c++ || return 1
    make -j"$JOBS" || return 1
    make install || return 1
}

verify_toolchain() {
    echo "  checking for $TOOLS/bin/gcc..."
    [ -x "$TOOLS/bin/gcc" ] || { echo "  gcc binary not found after build" >&2; return 1; }
    echo "  running: $TOOLS/bin/gcc --version"
    "$TOOLS/bin/gcc" --version || return 1
}

# --- Run the stage ---

echo "FeatherOS Stage 1: toolchain build"
echo "LFS_ROOT=$LFS_ROOT  JOBS=$JOBS"
echo

run_step "download-sources"     download_sources
run_step "extract-sources"      extract_sources
run_step "binutils-build"       build_binutils
run_step "linux-headers"        install_linux_headers
run_step "musl-build"           build_musl
run_step "gcc-build"            build_gcc
run_step "verify-toolchain"     verify_toolchain

echo
echo "Stage 1 complete. Toolchain installed in $TOOLS"
echo "Next: Stage 2 (temporary system build using this toolchain)."
