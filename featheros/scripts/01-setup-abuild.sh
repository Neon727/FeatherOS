#!/usr/bin/env bash
#
# 01-setup-abuild.sh
#
# Sets up the tooling needed to build .apk packages for FeatherOS:
# installs abuild (Alpine's package build tool) and generates a
# signing keypair. Every .apk in a repo must be signed — apk-tools
# refuses to install packages from an unsigned/untrusted repo.
#
# Run this once per build machine. The generated private key signs
# every package you build afterward, so back it up somewhere safe —
# losing it means re-signing (and redistributing) your whole repo
# under a new key.
#
# Usage: ./01-setup-abuild.sh
#
set -euo pipefail

KEY_DIR="${HOME}/.abuild"
PACKAGER_NAME="${PACKAGER_NAME:-FeatherOS Build}"
PACKAGER_EMAIL="${PACKAGER_EMAIL:-build@featheros.local}"

echo "== Checking for abuild =="
if ! command -v abuild >/dev/null 2>&1; then
    echo "abuild not found."
    echo "On Alpine/apk-based systems: apk add abuild"
    echo "On other distros: abuild isn't packaged everywhere — building it"
    echo "from Alpine's own aports repo is the usual path if your build"
    echo "host isn't already Alpine-based. Let's handle that if needed"
    echo "once we know what your build host is."
    exit 1
fi
echo "[FOUND] $(abuild --version 2>&1 | head -n1)"

echo
echo "== Setting up signing key =="
mkdir -p "$KEY_DIR"

if ls "$KEY_DIR"/*.rsa >/dev/null 2>&1; then
    echo "A signing key already exists in $KEY_DIR — skipping generation."
    echo "Existing key(s):"
    ls "$KEY_DIR"/*.rsa
else
    echo "Generating a new signing keypair as: $PACKAGER_NAME <$PACKAGER_EMAIL>"
    echo "(override with PACKAGER_NAME / PACKAGER_EMAIL env vars before running)"
    PACKAGER="$PACKAGER_NAME <$PACKAGER_EMAIL>" abuild-keygen -a -i
    echo "Key generated in $KEY_DIR"
fi

echo
echo "== Summary =="
echo "abuild is ready. Your public key (needed on any machine that will"
echo "install packages from your repo) is the .rsa.pub file in:"
echo "  $KEY_DIR"
echo
echo "Next: use the APKBUILD template in package-template/ to build your"
echo "first real package."
