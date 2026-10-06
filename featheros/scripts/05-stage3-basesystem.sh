#!/usr/bin/env bash
#
# 05-stage3-basesystem.sh
#
# Stage 3: builds the REAL base system (replacing Stage 2's minimal
# busybox temp system) using apk — the same method Alpine's own
# official tooling (alpine-make-rootfs, the official Docker image
# build) uses to construct a root filesystem: bootstrap with
# apk-tools-static against --root, pull in alpine-base.
#
# This is a deliberate departure from classic (glibc) LFS, where
# Stage 3 means hand-compiling every base package from source inside
# a chroot. Since FeatherOS already chose apk-tools as its package
# manager and chose to lean on Alpine's existing musl-compatible
# package ecosystem (see docs/decisions.md), hand-recompiling
# coreutils/etc. a second time here would just be redundant — apk
# bootstrap gets the same destination more directly, using the exact
# tooling the finished system will keep using anyway.
#
# Needs: root, network access (pulling packages), and apk-tools-static
# installed on the BUILD HOST (not the target) to do the bootstrapping.
#
# Checkpointed — safe to re-run after a failure.
#
# Usage:
#   ./05-stage3-basesystem.sh
#   ./05-stage3-basesystem.sh --status
#   ./05-stage3-basesystem.sh --reset [step...]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"

source "$SCRIPT_DIR/lib/checkpoint.sh"

case "${1:-}" in
    --status) list_steps; exit 0 ;;
    --reset)  shift; reset_steps "$@"; exit 0 ;;
esac

require_root() {
    [ "$(id -u)" -eq 0 ] || { echo "This script needs root." >&2; return 1; }
}

# --- Step functions ---

check_prerequisites() {
    require_root || return 1
    [ -d "$LFS_ROOT" ] || { echo "LFS_ROOT does not exist: $LFS_ROOT" >&2; return 1; }
    if ! command -v apk >/dev/null 2>&1; then
        echo "Host apk not found — this stage expects to run on an Alpine build host." >&2
        return 1
    fi
    echo "  root: ok, LFS_ROOT exists: ok, host apk: ok"
}

install_apk_static_on_host() {
    require_root || return 1
    if command -v apk.static >/dev/null 2>&1; then
        echo "  apk.static already present"
        return 0
    fi
    apk add apk-tools-static || return 1
    command -v apk.static >/dev/null 2>&1 || { echo "apk-tools-static installed but apk.static not found on PATH" >&2; return 1; }
}

configure_repositories() {
    require_root || return 1
    mkdir -p "$LFS_ROOT/etc/apk"
    if [ -f /etc/apk/repositories ]; then
        cp /etc/apk/repositories "$LFS_ROOT/etc/apk/repositories"
        echo "  copied host's repository list into \$LFS_ROOT/etc/apk/repositories:"
        cat "$LFS_ROOT/etc/apk/repositories"
    else
        echo "Host /etc/apk/repositories not found — can't determine mirror." >&2
        return 1
    fi
}

bootstrap_base_packages() {
    require_root || return 1
    local apk_static
    apk_static=$(command -v apk.static)
    # --initdb sets up apk's own package database inside the target
    # root; alpine-base pulls in musl, busybox (or full coreutils
    # depending on how it's configured), and openrc together as
    # Alpine's own minimal bootstrap set.
    "$apk_static" \
        --root "$LFS_ROOT" \
        --repositories-file "$LFS_ROOT/etc/apk/repositories" \
        --initdb \
        -U \
        add alpine-base openrc || return 1
}

verify_bootstrap() {
    require_root || return 1
    echo "  checking \$LFS_ROOT/sbin/apk exists..."
    [ -x "$LFS_ROOT/sbin/apk" ] || { echo "apk binary not found in bootstrapped root" >&2; return 1; }
    echo "  running: chroot \$LFS_ROOT apk info -v (sanity check apk works from inside)"
    chroot "$LFS_ROOT" /sbin/apk info -v || return 1
}

# --- Run ---

echo "FeatherOS Stage 3: base system bootstrap"
echo "LFS_ROOT=$LFS_ROOT"
echo

run_step "check-prerequisites"       check_prerequisites
run_step "install-apk-static-host"   install_apk_static_on_host
run_step "configure-repositories"    configure_repositories
run_step "bootstrap-base-packages"   bootstrap_base_packages
run_step "verify-bootstrap"          verify_bootstrap

echo
echo "Stage 3 complete. Base system bootstrapped in $LFS_ROOT via apk."
echo "Next: install FeatherOS-specific packages (splash, integrity"
echo "check, branding files) on top of this, then build the variant"
echo "split (headless vs desktop) from the package lists."
