#!/usr/bin/env bash
#
# 07-install-branding.sh
#
# Copies FeatherOS's branding/config files INTO the built root
# ($LFS_ROOT) — the splash, OpenRC services, MOTD, issue banner,
# os-release, and the X auto-start profile script all exist as
# source files in this repo, but nothing installs them into the
# system being built without this step. Must run after Stage 3 (the
# root needs to exist, with OpenRC's rc-update available inside it)
# and before 09-generate-integrity-manifest.sh (which needs these
# files actually present to hash them).
#
# Needs root (writing into $LFS_ROOT, chrooting to run rc-update).
#
# Checkpointed — safe to re-run after a failure.
#
# Usage:
#   ./07-install-branding.sh
#   ./07-install-branding.sh --status
#   ./07-install-branding.sh --reset [step...]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"
CONFIG_DIR="$PROJECT_ROOT/config"

source "$SCRIPT_DIR/lib/checkpoint.sh"

case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

require_root() {
    [ "$(id -u)" -eq 0 ] || { echo "This script needs root (writing into \$LFS_ROOT, chroot for rc-update)." >&2; return 1; }
}

# --- Step functions ---

check_prerequisites() {
    require_root || return 1
    [ -x "$LFS_ROOT/sbin/apk" ] || { echo "Base system root not found at $LFS_ROOT — run Stage 3 first." >&2; return 1; }
    [ -f "$CONFIG_DIR/os-release" ] || { echo "config/os-release not found — check PROJECT_ROOT resolution." >&2; return 1; }
    echo "  base system root: ok, config files: ok"
}

install_os_release() {
    require_root || return 1
    cp -v "$CONFIG_DIR/os-release" "$LFS_ROOT/etc/os-release"
}

install_motd_issue() {
    require_root || return 1
    cp -v "$CONFIG_DIR/etc-motd" "$LFS_ROOT/etc/motd"
    cp -v "$CONFIG_DIR/etc-issue" "$LFS_ROOT/etc/issue"
}

install_splash() {
    require_root || return 1
    mkdir -p "$LFS_ROOT/usr/bin/lib"
    # These three need to land together at these exact relative
    # paths — splash-feather.sh and boot-integrity-check.sh both
    # resolve their lib/colors.sh dependency relative to their own
    # install location at runtime.
    cp -v "$SCRIPT_DIR/splash-feather.sh" "$LFS_ROOT/usr/bin/featheros-splash.sh"
    cp -v "$SCRIPT_DIR/boot-integrity-check.sh" "$LFS_ROOT/usr/bin/boot-integrity-check.sh"
    cp -v "$SCRIPT_DIR/lib/colors.sh" "$LFS_ROOT/usr/bin/lib/colors.sh"
    chmod +x "$LFS_ROOT/usr/bin/featheros-splash.sh" "$LFS_ROOT/usr/bin/boot-integrity-check.sh"
}

install_openrc_services() {
    require_root || return 1
    mkdir -p "$LFS_ROOT/etc/init.d"
    cp -v "$CONFIG_DIR/openrc/featheros-splash" "$LFS_ROOT/etc/init.d/featheros-splash"
    cp -v "$CONFIG_DIR/openrc/featheros-splash-stop" "$LFS_ROOT/etc/init.d/featheros-splash-stop"
    chmod +x "$LFS_ROOT/etc/init.d/featheros-splash" "$LFS_ROOT/etc/init.d/featheros-splash-stop"

    # Enable both services inside the target root via chroot — this
    # is what actually makes OpenRC run them at boot (rc-update just
    # creates symlinks under etc/runlevels/, but it needs to run
    # against the target root's own openrc db, hence the chroot).
    chroot "$LFS_ROOT" /sbin/rc-update add featheros-splash boot || return 1
    chroot "$LFS_ROOT" /sbin/rc-update add featheros-splash-stop default || return 1
}

install_xorg_autostart() {
    require_root || return 1
    mkdir -p "$LFS_ROOT/etc/profile.d"
    cp -v "$CONFIG_DIR/etc-profile.d-start-xorg.sh" "$LFS_ROOT/etc/profile.d/start-xorg.sh"
    chmod +x "$LFS_ROOT/etc/profile.d/start-xorg.sh"
    echo "  NOTE: this only does anything on the desktop variant (needs"
    echo "  Xorg + i3 actually installed) — harmless no-op on headless,"
    echo "  since startx won't exist there to exec into."
}

verify_install() {
    local missing=0
    for f in \
        "etc/os-release" "etc/motd" "etc/issue" \
        "usr/bin/featheros-splash.sh" "usr/bin/boot-integrity-check.sh" "usr/bin/lib/colors.sh" \
        "etc/init.d/featheros-splash" "etc/init.d/featheros-splash-stop" \
        "etc/profile.d/start-xorg.sh"
    do
        if [ ! -e "$LFS_ROOT/$f" ]; then
            echo "  MISSING: $f" >&2
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -eq 0 ] || { echo "  $missing file(s) missing after install" >&2; return 1; }
    echo "  all branding/config files present"
}

# --- Run ---

echo "FeatherOS branding/config install"
echo "LFS_ROOT=$LFS_ROOT"
echo

run_step "check-prerequisites"    check_prerequisites
run_step "install-os-release"     install_os_release
run_step "install-motd-issue"     install_motd_issue
run_step "install-splash"         install_splash
run_step "install-openrc-services" install_openrc_services
run_step "install-xorg-autostart" install_xorg_autostart
run_step "verify-install"         verify_install

echo
echo "Branding/config installed into $LFS_ROOT"
echo "Next: 09-generate-integrity-manifest.sh (needs these files to hash them)."
