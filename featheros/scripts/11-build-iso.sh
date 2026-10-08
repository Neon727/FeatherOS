#!/usr/bin/env bash
#
# 07-build-iso.sh
#
# Packages a finished FeatherOS root filesystem into a bootable ISO
# using grub-mkrescue — GRUB's own wrapper around xorriso that
# builds a hybrid image bootable via both legacy BIOS and UEFI from
# one file (handles the fiddly dual-boot-mode setup for us, rather
# than us hand-building xorriso flags for it).
#
# Requires, on the Alpine build host:
#   apk add grub grub-bios grub-efi xorriso mtools dosfstools
#
# What this script actually does:
#   1. Stages an ISO layout directory: /boot (kernel + initramfs +
#      grub.cfg) and /featheros-root (the built system, copied in —
#      this is what gets installed to disk, or run live from).
#   2. Writes a grub.cfg with boot menu entries, including a
#      "Verify media integrity" entry wired to iso-integrity-check.sh.
#   3. Runs grub-mkrescue to produce the final .iso.
#   4. Embeds the checksum (06-embed-iso-checksum.sh) as the last
#      step, so it covers the finished, final ISO content.
#
# Checkpointed like earlier stages — safe to re-run after a failure.
#
# Usage:
#   ./07-build-iso.sh <built-root-path> <kernel-path> <output.iso>
#   ./07-build-iso.sh --status
#   ./07-build-iso.sh --reset [step...]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"
ISO_STAGE="$LFS_ROOT/iso-stage"

source "$SCRIPT_DIR/lib/checkpoint.sh"

case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

BUILT_ROOT="${1:-}"
KERNEL_PATH="${2:-}"
OUTPUT_ISO="${3:-$LFS_ROOT/featheros.iso}"

if [ -z "$BUILT_ROOT" ] || [ -z "$KERNEL_PATH" ]; then
    echo "Usage: $0 <built-root-path> <kernel-path> [output.iso]" >&2
    exit 1
fi

require_tool() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; echo "Install: apk add grub grub-bios grub-efi xorriso mtools dosfstools" >&2; return 1; }
}

# --- Step functions ---

check_prerequisites() {
    require_tool grub-mkrescue || return 1
    [ -d "$BUILT_ROOT" ] || { echo "Built root not found: $BUILT_ROOT" >&2; return 1; }
    [ -f "$KERNEL_PATH" ] || { echo "Kernel not found: $KERNEL_PATH" >&2; return 1; }
    echo "  grub-mkrescue: ok, built root: ok, kernel: ok"
}

stage_layout() {
    mkdir -p "$ISO_STAGE/boot/grub"
    mkdir -p "$ISO_STAGE/featheros-root"

    echo "  copying kernel..."
    cp -v "$KERNEL_PATH" "$ISO_STAGE/boot/vmlinuz"

    if [ -f "$LFS_ROOT/boot/initramfs" ]; then
        echo "  copying initramfs..."
        cp -v "$LFS_ROOT/boot/initramfs" "$ISO_STAGE/boot/initramfs"
    else
        echo "  [WARN] no initramfs found at $LFS_ROOT/boot/initramfs — boot entry will still reference it; build one before this ISO is actually bootable." >&2
    fi

    echo "  copying built root filesystem (this can take a while for the desktop variant)..."
    cp -a "$BUILT_ROOT/." "$ISO_STAGE/featheros-root/"
}

write_grub_cfg() {
    cat > "$ISO_STAGE/boot/grub/grub.cfg" << 'GRUBCFG'
set timeout=10
set default=0

# Basic color theme matching the FeatherOS palette (docs/branding.md).
# GRUB's text-mode menu only has a fixed set of named colors, not
# arbitrary hex — "yellow" is the closest standard name to the gold
# accent used everywhere else (splash, wallpaper).
insmod all_video
set gfxmode=auto
terminal_output gfxterm
set color_normal=light-gray/black
set color_highlight=black/yellow

menuentry "FeatherOS" {
    linux /boot/vmlinuz root=/dev/ram0 quiet
    initrd /boot/initramfs
}

menuentry "FeatherOS (verbose boot)" {
    linux /boot/vmlinuz root=/dev/ram0
    initrd /boot/initramfs
}

menuentry "Verify media integrity" {
    linux /boot/vmlinuz root=/dev/ram0 featheros.checkmedia
    initrd /boot/initramfs
}
GRUBCFG
    echo "  wrote $ISO_STAGE/boot/grub/grub.cfg"
    echo "  (the 'Verify media integrity' entry passes a kernel boot"
    echo "   parameter your init/initramfs should check for, to run"
    echo "   iso-integrity-check.sh before continuing to normal boot —"
    echo "   that wiring happens in the initramfs init script, not here)"
}

run_grub_mkrescue() {
    mkdir -p "$(dirname "$OUTPUT_ISO")"
    grub-mkrescue -o "$OUTPUT_ISO" "$ISO_STAGE" || return 1
    echo "  built: $OUTPUT_ISO"
    ls -lh "$OUTPUT_ISO"
}

embed_checksum() {
    if ! command -v implantisomd5 >/dev/null 2>&1; then
        echo "  [WARN] implantisomd5 not found — skipping checksum embed." >&2
        echo "  Install: apk add isomd5sum, then run:" >&2
        echo "    $SCRIPT_DIR/06-embed-iso-checksum.sh $OUTPUT_ISO" >&2
        return 0
    fi
    "$SCRIPT_DIR/06-embed-iso-checksum.sh" "$OUTPUT_ISO"
}

# --- Run ---

echo "FeatherOS ISO build"
echo "Built root: $BUILT_ROOT"
echo "Kernel:     $KERNEL_PATH"
echo "Output:     $OUTPUT_ISO"
echo

run_step "check-prerequisites"  check_prerequisites
run_step "stage-layout"         stage_layout
run_step "write-grub-cfg"       write_grub_cfg
run_step "run-grub-mkrescue"    run_grub_mkrescue
run_step "embed-checksum"       embed_checksum

echo
echo "ISO build complete: $OUTPUT_ISO"
