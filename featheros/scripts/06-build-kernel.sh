#!/usr/bin/env bash
#
# 06-build-kernel.sh
#
# Compiles the actual bootable kernel (bzImage) and installs its
# modules into the real base system root — this is the step that
# was missing before: Stage 1 only ran `make headers_install`
# (userspace API headers, needed to build musl/GCC), not a real
# kernel build. Nothing before this point produces a bootable kernel
# image at all.
#
# Needs: root, Stage 1's kernel source (already extracted in
# $LFS_ROOT/sources), and Stage 3's base system root (to install
# modules into).
#
# Follows the approach in config/kernel-notes-public.md: broad
# driver coverage as loadable modules, zram enabled, debug symbols
# off. Starts from defconfig (a sane generic x86_64 baseline that
# already builds most drivers as modules) and layers a few targeted
# tweaks on top via the kernel's own `scripts/config` tool, rather
# than hand-editing the whole config — much less fragile.
#
# Checkpointed — safe to re-run after a failure.
#
# Usage:
#   ./06-build-kernel.sh
#   ./06-build-kernel.sh --status
#   ./06-build-kernel.sh --reset [step...]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"
SOURCES="$LFS_ROOT/sources"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
LINUX_VER="6.18"   # must match the version Stage 1 downloaded

source "$SCRIPT_DIR/lib/checkpoint.sh"

case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

require_root() {
    [ "$(id -u)" -eq 0 ] || { echo "This script needs root (installing kernel modules)." >&2; return 1; }
}

KSRC="$SOURCES/linux-${LINUX_VER}"

# --- Step functions ---

check_prerequisites() {
    require_root || return 1
    [ -d "$KSRC" ] || { echo "Kernel source not found at $KSRC — run Stage 1 first." >&2; return 1; }
    [ -x "$LFS_ROOT/sbin/apk" ] || { echo "Base system root not found at $LFS_ROOT — run Stage 3 first." >&2; return 1; }
    for tool in bc flex bison; do
        command -v "$tool" >/dev/null 2>&1 || { echo "Missing build tool: $tool (apk add $tool)" >&2; return 1; }
    done
    echo "  kernel source: ok, base system root: ok, build tools: ok"
}

configure_kernel() {
    cd "$KSRC" || return 1
    make defconfig || return 1

    # Targeted tweaks on top of defconfig, matching
    # config/kernel-notes-public.md. scripts/config is the kernel's
    # own safe way to flip individual options without hand-editing
    # the whole file.
    ./scripts/config --enable CONFIG_ZRAM
    ./scripts/config --enable CONFIG_HIGHMEM64G 2>/dev/null || true   # only meaningful on some configs; harmless if absent
    ./scripts/config --disable CONFIG_DEBUG_INFO
    ./scripts/config --disable CONFIG_DEBUG_KERNEL

    make olddefconfig || return 1
    echo "  kernel configured (defconfig + zram/debug-symbol tweaks)"
}

build_kernel() {
    cd "$KSRC" || return 1
    make -j"$JOBS" bzImage modules || return 1
}

install_kernel() {
    require_root || return 1
    cd "$KSRC" || return 1

    mkdir -p "$LFS_ROOT/boot"
    cp -v arch/x86/boot/bzImage "$LFS_ROOT/boot/vmlinuz" || return 1

    # Modules install straight into the real base system root (the
    # one Stage 3 bootstrapped), not into $LFS_ROOT/tools — this is
    # what the INSTALLED system boots with, not the build toolchain.
    make modules_install INSTALL_MOD_PATH="$LFS_ROOT" || return 1

    echo "  kernel installed: $LFS_ROOT/boot/vmlinuz"
    echo "  modules installed under: $LFS_ROOT/lib/modules/"
}

verify_kernel() {
    [ -f "$LFS_ROOT/boot/vmlinuz" ] || { echo "vmlinuz not found after install" >&2; return 1; }
    echo "  checking kernel image..."
    file "$LFS_ROOT/boot/vmlinuz" 2>/dev/null || ls -lh "$LFS_ROOT/boot/vmlinuz"
    local mod_count
    mod_count=$(find "$LFS_ROOT/lib/modules" -name '*.ko*' 2>/dev/null | wc -l)
    echo "  module files installed: $mod_count"
    [ "$mod_count" -gt 0 ] || { echo "no module files found — modules_install may have failed silently" >&2; return 1; }
}

# --- Run ---

echo "FeatherOS kernel build"
echo "LFS_ROOT=$LFS_ROOT  JOBS=$JOBS"
echo

run_step "check-prerequisites"  check_prerequisites
run_step "configure-kernel"     configure_kernel
run_step "build-kernel"         build_kernel
run_step "install-kernel"       install_kernel
run_step "verify-kernel"        verify_kernel

echo
echo "Kernel build complete: $LFS_ROOT/boot/vmlinuz"
echo "Next: initramfs build (08-build-initramfs.sh), then the ISO build"
echo "(11-build-iso.sh), which expects the kernel at this exact path."
