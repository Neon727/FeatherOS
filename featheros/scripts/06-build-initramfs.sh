#!/usr/bin/env bash
#
# 08-build-initramfs.sh
#
# Builds the actual initramfs image: a minimal filesystem tree
# (busybox + our init script + the integrity-check scripts + basic
# device nodes), packaged into the cpio+gzip format the Linux kernel
# expects to load at boot, before the real root is even mounted.
#
# Requires root (device nodes) and a completed Stage 2 (uses the
# static busybox built there).
#
# Requires on the build host: cpio (apk add cpio — gzip is part of
# the base toolset already).
#
# Checkpointed — safe to re-run after a failure.
#
# Usage:
#   ./08-build-initramfs.sh [output-path]   (default: $LFS_ROOT/boot/initramfs)
#   ./08-build-initramfs.sh --status
#   ./08-build-initramfs.sh --reset [step...]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"
INITRAMFS_TREE="$LFS_ROOT/initramfs-tree"
OUTPUT_PATH="${1:-$LFS_ROOT/boot/initramfs}"

source "$SCRIPT_DIR/lib/checkpoint.sh"

case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

require_root() {
    [ "$(id -u)" -eq 0 ] || { echo "This step needs root (device nodes)." >&2; return 1; }
}

# --- Step functions ---

check_prerequisites() {
    require_root || return 1
    [ -x "$LFS_ROOT/bin/busybox" ] || { echo "Static busybox not found at $LFS_ROOT/bin/busybox — run Stage 2 first." >&2; return 1; }
    [ -f "$SCRIPT_DIR/initramfs-init.sh" ] || { echo "initramfs-init.sh not found next to this script." >&2; return 1; }
    [ -f "$SCRIPT_DIR/iso-integrity-check.sh" ] || { echo "iso-integrity-check.sh not found next to this script." >&2; return 1; }
    [ -f "$SCRIPT_DIR/lib/colors.sh" ] || { echo "lib/colors.sh not found." >&2; return 1; }
    command -v cpio >/dev/null 2>&1 || { echo "cpio not found — apk add cpio" >&2; return 1; }
    echo "  all prerequisites present"
}

prepare_tree() {
    require_root || return 1
    rm -rf "$INITRAMFS_TREE"
    mkdir -pv "$INITRAMFS_TREE"/bin
    mkdir -pv "$INITRAMFS_TREE"/sbin
    mkdir -pv "$INITRAMFS_TREE"/dev
    mkdir -pv "$INITRAMFS_TREE"/proc
    mkdir -pv "$INITRAMFS_TREE"/sys
    mkdir -pv "$INITRAMFS_TREE"/newroot
    mkdir -pv "$INITRAMFS_TREE"/scripts
}

install_busybox() {
    require_root || return 1
    cp -v "$LFS_ROOT/bin/busybox" "$INITRAMFS_TREE/bin/busybox"

    # Applet symlinks point to the ABSOLUTE path /bin/busybox — correct
    # for inside the initramfs, where / is its own root at boot, but
    # that means `[ -e ... ]` checks run from the build host can't
    # verify them directly (the host's own / usually doesn't have
    # busybox at that exact path, so the symlink looks "dangling" from
    # here even though it's fine once booted). So we verify applet
    # presence against busybox's own --list output instead of statting
    # the symlinks from the host's perspective.
    local applet_list
    applet_list=$("$INITRAMFS_TREE/bin/busybox" --list)

    echo "$applet_list" | while read -r applet; do
        ln -sf /bin/busybox "$INITRAMFS_TREE/bin/$applet"
    done
    ln -sf /bin/busybox "$INITRAMFS_TREE/bin/sh"

    for needed in switch_root mount mkdir cat; do
        if ! echo "$applet_list" | grep -qx "$needed"; then
            echo "  busybox build is missing the '$needed' applet — check its config." >&2
            return 1
        fi
    done
}

install_scripts() {
    require_root || return 1
    cp -v "$SCRIPT_DIR/initramfs-init.sh" "$INITRAMFS_TREE/init"
    chmod +x "$INITRAMFS_TREE/init"

    cp -v "$SCRIPT_DIR/iso-integrity-check.sh" "$INITRAMFS_TREE/scripts/iso-integrity-check.sh"
    chmod +x "$INITRAMFS_TREE/scripts/iso-integrity-check.sh"

    mkdir -p "$INITRAMFS_TREE/scripts/lib"
    cp -v "$SCRIPT_DIR/lib/colors.sh" "$INITRAMFS_TREE/scripts/lib/colors.sh"

    # iso-integrity-check.sh sources lib/colors.sh relative to its own
    # location (SCRIPT_DIR/lib/colors.sh) — this layout matches that.
}

install_checkisomd5() {
    require_root || return 1
    if command -v checkisomd5 >/dev/null 2>&1; then
        local bin_path
        bin_path=$(command -v checkisomd5)
        cp -v "$bin_path" "$INITRAMFS_TREE/bin/checkisomd5"
        echo "  copied checkisomd5 from $bin_path"
        echo "  [NOTE] if it's dynamically linked, its shared libs also"
        echo "  need to be present in the initramfs — verify with:"
        echo "    ldd $bin_path"
        echo "  and copy any non-libc deps into $INITRAMFS_TREE/lib/"
    else
        echo "  [WARN] checkisomd5 not found on build host — the media" >&2
        echo "  integrity check will warn and skip at boot without it." >&2
        echo "  Install: apk add isomd5sum, then re-run this step:" >&2
        echo "    $0 --reset install-checkisomd5" >&2
    fi
}

make_device_nodes() {
    require_root || return 1
    local dev="$INITRAMFS_TREE/dev"
    [ -e "$dev/null" ]    || mknod -m 666 "$dev/null" c 1 3
    [ -e "$dev/zero" ]    || mknod -m 666 "$dev/zero" c 1 5
    [ -e "$dev/console" ] || mknod -m 600 "$dev/console" c 5 1
    [ -e "$dev/tty" ]     || mknod -m 666 "$dev/tty" c 5 0
}

build_cpio_image() {
    require_root || return 1
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    ( cd "$INITRAMFS_TREE" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUTPUT_PATH" ) || return 1
    echo "  built: $OUTPUT_PATH"
    ls -lh "$OUTPUT_PATH"
}

# --- Run ---

echo "FeatherOS initramfs build"
echo "LFS_ROOT=$LFS_ROOT"
echo "Output: $OUTPUT_PATH"
echo

run_step "check-prerequisites"  check_prerequisites
run_step "prepare-tree"         prepare_tree
run_step "install-busybox"      install_busybox
run_step "install-scripts"      install_scripts
run_step "install-checkisomd5"  install_checkisomd5
run_step "make-device-nodes"    make_device_nodes
run_step "build-cpio-image"     build_cpio_image

echo
echo "Initramfs build complete: $OUTPUT_PATH"
