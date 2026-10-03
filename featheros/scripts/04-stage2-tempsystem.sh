#!/usr/bin/env bash
#
# 04-stage2-tempsystem.sh
#
# Stage 2: builds a minimal temporary system using the Stage 1
# toolchain — just enough to chroot into and build the real base
# system from inside (Stage 3). This stage needs root (for chroot
# dir setup / device nodes) and needs Stage 1 to have completed:
# it uses $LFS_ROOT/tools/bin/gcc, not the host's compiler.
#
# FeatherOS uses busybox as the temp-system userland (one static
# binary providing core utilities) rather than building coreutils,
# bash, etc. separately here — matches the lean/minimal approach,
# and the full base system still gets built properly in Stage 3.
#
# Every step is checkpointed — safe to re-run after a failure.
#
# Usage:
#   ./04-stage2-tempsystem.sh
#   ./04-stage2-tempsystem.sh --status
#   ./04-stage2-tempsystem.sh --reset [step...]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"
SOURCES="$LFS_ROOT/sources"
TOOLS="$LFS_ROOT/tools"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

source "$SCRIPT_DIR/lib/checkpoint.sh"

BUSYBOX_VER="1.36.1"   # busybox.net's current designated-stable release
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2"

case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This step needs root (chroot dir setup / device nodes)." >&2
        echo "Re-run this script with sudo." >&2
        return 1
    fi
}

require_stage1() {
    if [ ! -x "$TOOLS/bin/gcc" ]; then
        echo "Stage 1 toolchain not found at $TOOLS/bin/gcc" >&2
        echo "Run 03-stage1-toolchain.sh first." >&2
        return 1
    fi
}

# --- Step functions ---

check_prerequisites() {
    require_root || return 1
    require_stage1 || return 1
    echo "  root: ok, Stage 1 toolchain: ok"
}

download_busybox() {
    cd "$SOURCES" || return 1
    local fname="busybox-${BUSYBOX_VER}.tar.bz2"
    if [ -f "$fname" ]; then
        echo "  already downloaded: $fname"
    else
        echo "  downloading: $fname"
        curl -L --fail -o "$fname" "$BUSYBOX_URL" || return 1
    fi
    local actual
    actual=$(sha256sum "$fname" | awk '{print $1}')
    local checksum_file="$SOURCES/CHECKSUMS.sha256"
    touch "$checksum_file"
    if grep -q " $fname\$" "$checksum_file" 2>/dev/null; then
        local expected
        expected=$(grep " $fname\$" "$checksum_file" | awk '{print $1}')
        [ "$actual" = "$expected" ] || { echo "  CHECKSUM MISMATCH for $fname" >&2; return 1; }
    else
        echo "$actual  $fname" >> "$checksum_file"
    fi
}

extract_busybox() {
    cd "$SOURCES" || return 1
    tar xf "busybox-${BUSYBOX_VER}.tar.bz2" || return 1
}

build_busybox() {
    local src="$SOURCES/busybox-${BUSYBOX_VER}"
    cd "$src" || return 1
    export PATH="$TOOLS/bin:$PATH"
    export CC="$TOOLS/bin/gcc"
    make defconfig || return 1
    # Static binary — the temp system has no shared libs installed
    # yet, so busybox needs to be fully self-contained.
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    make -j"$JOBS" || return 1
}

prepare_chroot_skeleton() {
    require_root || return 1
    local dirs=(
        bin sbin usr/bin usr/sbin
        dev proc sys run tmp
        etc var/log
    )
    for d in "${dirs[@]}"; do
        mkdir -pv "$LFS_ROOT/$d"
    done
    chmod 1777 "$LFS_ROOT/tmp"
}

install_busybox_into_chroot() {
    require_root || return 1
    local src="$SOURCES/busybox-${BUSYBOX_VER}"
    cd "$src" || return 1
    cp -v busybox "$LFS_ROOT/bin/busybox"
    # Symlink every applet busybox supports to the single binary —
    # this is what makes `ls`, `cp`, `sh`, etc. all work in the
    # temp system from one ~1-2MB static executable.
    "$LFS_ROOT/bin/busybox" --list | while read -r applet; do
        ln -sf /bin/busybox "$LFS_ROOT/bin/$applet"
    done
    # sh needs to exist unconditionally for the chroot to be usable
    ln -sf /bin/busybox "$LFS_ROOT/bin/sh"
}

make_device_nodes() {
    require_root || return 1
    local dev="$LFS_ROOT/dev"
    [ -e "$dev/null" ]    || mknod -m 666 "$dev/null" c 1 3
    [ -e "$dev/zero" ]    || mknod -m 666 "$dev/zero" c 1 5
    [ -e "$dev/random" ]  || mknod -m 666 "$dev/random" c 1 8
    [ -e "$dev/urandom" ] || mknod -m 666 "$dev/urandom" c 1 9
    [ -e "$dev/console" ] || mknod -m 600 "$dev/console" c 5 1
    [ -e "$dev/tty" ]     || mknod -m 666 "$dev/tty" c 5 0
}

verify_tempsystem() {
    require_root || return 1
    echo "  testing chroot with busybox sh..."
    chroot "$LFS_ROOT" /bin/sh -c 'echo "chroot sh works: $(busybox | head -1)"' || return 1
}

# --- Run the stage ---

echo "FeatherOS Stage 2: temporary system build"
echo "LFS_ROOT=$LFS_ROOT  JOBS=$JOBS"
echo

run_step "check-prerequisites"       check_prerequisites
run_step "download-busybox"          download_busybox
run_step "extract-busybox"           extract_busybox
run_step "build-busybox"             build_busybox
run_step "prepare-chroot-skeleton"   prepare_chroot_skeleton
run_step "install-busybox-chroot"    install_busybox_into_chroot
run_step "make-device-nodes"         make_device_nodes
run_step "verify-tempsystem"         verify_tempsystem

echo
echo "Stage 2 complete. Minimal chroot-able system ready in $LFS_ROOT"
echo "Next: Stage 3 (chroot in, build the real base system using the"
echo "Stage 1 toolchain — coreutils, musl shared libs, init, etc.)."
