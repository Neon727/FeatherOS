#!/usr/bin/env bash
#
# 02-get-started.sh
#
# Run this on the actual Alpine build VM once you've copied this
# project onto it. Does everything needed before Stage 1 (the LFS
# toolchain build) can start:
#   1. Installs the base build tools apk knows about (build-base, etc)
#   2. Runs host-prep to verify everything LFS needs is present
#   3. Sets up abuild + your signing key
#   4. Creates the LFS working directory layout
#
# Usage: ./02-get-started.sh
#   (needs root/sudo for the apk add step; the rest runs as your user)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"

echo "== Step 1: base build tools =="
if command -v apk >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
        apk add --no-cache build-base abuild git curl bash
    else
        echo "Not running as root — run this yourself first, then re-run this script:"
        echo "  sudo apk add --no-cache build-base abuild git curl bash"
        exit 1
    fi
else
    echo "[SKIP] apk not found — this doesn't look like an Alpine host."
    echo "Install the equivalent build tools manually for your distro, then continue."
fi

echo
echo "== Step 2: host-prep check =="
bash "$SCRIPT_DIR/00-host-prep.sh"

echo
echo "== Step 3: abuild + signing key setup =="
bash "$SCRIPT_DIR/01-setup-abuild.sh"

echo
echo "== Step 4: LFS working directory =="
echo "Setting up $LFS_ROOT (override with LFS_ROOT=/some/path before running)"
if [ "$(id -u)" -eq 0 ]; then
    mkdir -pv "$LFS_ROOT"
    mkdir -pv "$LFS_ROOT/sources"   # downloaded package tarballs land here
    mkdir -pv "$LFS_ROOT/tools"     # Stage 1 toolchain gets installed here
    chmod -v a+wt "$LFS_ROOT/sources"
else
    echo "Not running as root — create it yourself:"
    echo "  sudo mkdir -pv $LFS_ROOT $LFS_ROOT/sources $LFS_ROOT/tools"
    echo "  sudo chmod -v a+wt $LFS_ROOT/sources"
fi

echo
echo "== Ready =="
echo "Build host is prepped. Working directory: $LFS_ROOT"
echo "Next: Stage 1 — downloading and building the toolchain."
echo "it's the first stage that actually takes real"
echo "compile time (expect a few hours)."
