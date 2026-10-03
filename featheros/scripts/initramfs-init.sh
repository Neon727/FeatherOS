#!/bin/sh
#
# initramfs-init.sh
#
# This becomes /init inside the initramfs — the very first userspace
# process the kernel runs, PID 1, before the real root filesystem is
# even mounted. Written in plain POSIX sh (not bash) since only
# busybox's shell is guaranteed available this early in boot.
#
# Responsibilities, in order:
#   1. Mount the virtual filesystems (/proc, /sys, /dev) needed for
#      anything else here to work at all.
#   2. Check /proc/cmdline for featheros.checkmedia — if present
#      (set by the "Verify media integrity" GRUB entry), run the
#      ISO integrity check before going any further.
#   3. Locate and mount the real root filesystem.
#   4. switch_root into it, handing off to the real init.
#
# This script and its dependencies (iso-integrity-check.sh,
# lib/colors.sh, checkisomd5) need to actually be copied into the
# initramfs image at build time — this file alone doesn't put itself
# there. That packaging step belongs in the Stage 2/3 initramfs
# build, not here.
#
set -u

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mount -t tmpfs none /dev

CMDLINE=$(cat /proc/cmdline)

# --- Media integrity check, only if requested ---
case "$CMDLINE" in
    *featheros.checkmedia*)
        echo "FeatherOS: checkmedia requested — running integrity check"
        if [ -x /scripts/iso-integrity-check.sh ]; then
            /scripts/iso-integrity-check.sh /dev/sr0
            check_result=$?
            if [ "$check_result" -ne 0 ]; then
                echo "Integrity check aborted boot. Dropping to a shell."
                exec /bin/sh
            fi
        else
            echo "[WARN] checkmedia requested but /scripts/iso-integrity-check.sh"
            echo "is missing from the initramfs — skipping check."
        fi
        ;;
esac

# --- Locate and mount the real root ---
# ROOT_DEV can be overridden via the "root=" kernel parameter (grub.cfg
# currently passes root=/dev/ram0 as a placeholder — this needs to
# point at wherever the real root actually ends up: a squashfs on the
# ISO for live/install boot, or the installed disk partition post-install).
ROOT_DEV="/dev/ram0"
for param in $CMDLINE; do
    case "$param" in
        root=*) ROOT_DEV="${param#root=}" ;;
    esac
done

mkdir -p /newroot
if ! mount "$ROOT_DEV" /newroot 2>/dev/null; then
    echo "FeatherOS: failed to mount root at $ROOT_DEV"
    echo "Dropping to a rescue shell."
    exec /bin/sh
fi

# --- Hand off to the real system ---
umount /proc /sys /dev 2>/dev/null
exec switch_root /newroot /sbin/init
