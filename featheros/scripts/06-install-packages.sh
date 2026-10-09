#!/usr/bin/env bash
#
# 06-install-packages.sh
#
# Installs the actual package set into the built root via apk:
# package-lists/base.txt (shared) plus whichever variant you pick
# (headless.txt or desktop.txt). Before this step, Stage 3 only
# bootstrapped alpine-base + openrc — this is what fills in bash,
# coreutils, nano, i3/Xorg (desktop), dcron (headless), etc.
#
# base.txt has a few entries that are NOT real apk package names and
# get skipped deliberately:
#   - linux-kernel: handled by 07-build-kernel.sh, not apk
#   - musl, apk-tools: already present from Stage 3's bootstrap
#
# Needs root (installing into $LFS_ROOT) and a completed Stage 3.
#
# Checkpointed — safe to re-run after a failure. The chosen variant
# is remembered (written to $LFS_ROOT/.featheros-variant) so a later
# resume doesn't need you to pass it again.
#
# Usage:
#   ./06-install-packages.sh <headless|desktop>
#   ./06-install-packages.sh --status
#   ./06-install-packages.sh --reset [step...]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"
PKG_LISTS="$PROJECT_ROOT/package-lists"
VARIANT_FILE="$LFS_ROOT/.featheros-variant"

source "$SCRIPT_DIR/lib/checkpoint.sh"

case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

# Entries in base.txt that aren't real apk package names — handled
# elsewhere in the pipeline, or already present from Stage 3.
SKIP_PACKAGES="linux-kernel musl apk-tools"

VARIANT="${1:-}"
if [ -z "$VARIANT" ]; then
    if [ -f "$VARIANT_FILE" ]; then
        VARIANT=$(cat "$VARIANT_FILE")
        echo "No variant given — resuming with previously chosen: $VARIANT"
    else
        echo "Usage: $0 <headless|desktop>" >&2
        exit 1
    fi
fi
if [ "$VARIANT" != "headless" ] && [ "$VARIANT" != "desktop" ]; then
    echo "Variant must be 'headless' or 'desktop', got: $VARIANT" >&2
    exit 1
fi

require_root() {
    [ "$(id -u)" -eq 0 ] || { echo "This script needs root (installing into \$LFS_ROOT)." >&2; return 1; }
}

# Strips comments and blank lines from a package list, keeping just
# the package name (first whitespace-delimited token) from each
# remaining line, and drops anything in SKIP_PACKAGES.
parse_package_list() {
    local file="$1"
    local pkg
    while IFS= read -r line; do
        line="${line%%#*}"            # strip inline/full-line comments
        pkg=$(echo "$line" | awk '{print $1}')
        [ -z "$pkg" ] && continue
        case " $SKIP_PACKAGES " in
            *" $pkg "*) continue ;;
        esac
        echo "$pkg"
    done < "$file"
}

# --- Step functions ---

check_prerequisites() {
    require_root || return 1
    [ -x "$LFS_ROOT/sbin/apk" ] || { echo "Base system root not found at $LFS_ROOT — run Stage 3 first." >&2; return 1; }
    [ -f "$PKG_LISTS/base.txt" ] || { echo "package-lists/base.txt not found." >&2; return 1; }
    [ -f "$PKG_LISTS/$VARIANT.txt" ] || { echo "package-lists/$VARIANT.txt not found." >&2; return 1; }
    echo "$VARIANT" > "$VARIANT_FILE"
    echo "  base system root: ok, package lists: ok, variant: $VARIANT"
}
setup_chroot_dns() {
    require_root || return 1
    mkdir -p "$LFS_ROOT/etc"
    # Copy the host's resolver config into the chroot
    cp -L /etc/resolv.conf "$LFS_ROOT/etc/resolv.conf"
    echo "  copied host resolv.conf into $LFS_ROOT/etc/"
}

install_base_packages() {
    require_root || return 1
    local pkgs
    pkgs=$(parse_package_list "$PKG_LISTS/base.txt")
    echo "  installing base packages: $pkgs"
    # shellcheck disable=SC2086
    chroot "$LFS_ROOT" apk add $pkgs || return 1
}

install_variant_packages() {
    require_root || return 1
    local pkgs
    pkgs=$(parse_package_list "$PKG_LISTS/$VARIANT.txt")
    echo "  installing $VARIANT packages: $pkgs"
    # shellcheck disable=SC2086
    chroot "$LFS_ROOT" apk add $pkgs || return 1
}

verify_install() {
    echo "  spot-checking a package from each list actually landed..."
    chroot "$LFS_ROOT" apk info -e bash >/dev/null 2>&1 || { echo "bash not found after install" >&2; return 1; }
    if [ "$VARIANT" = "desktop" ]; then
        chroot "$LFS_ROOT" apk info -e i3-wm >/dev/null 2>&1 || { echo "i3-wm not found after install" >&2; return 1; }
    else
        chroot "$LFS_ROOT" apk info -e dcron >/dev/null 2>&1 || { echo "dcron not found after install" >&2; return 1; }
    fi
    echo "  spot checks passed"
}

# --- Run ---

echo "FeatherOS package install — variant: $VARIANT"
echo "LFS_ROOT=$LFS_ROOT"
echo

run_step "check-prerequisites"      check_prerequisites
run_step "setup-chroot-dns"         setup_chroot_dns
run_step "install-base-packages"    install_base_packages
run_step "install-variant-packages" install_variant_packages
run_step "verify-install"           verify_install

echo
echo "Package install complete for variant: $VARIANT"
echo "Next: 07-build-kernel.sh (if not already done), then 08-install-branding.sh."
