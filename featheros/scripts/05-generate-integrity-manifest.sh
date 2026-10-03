#!/usr/bin/env bash
#
# 05-generate-integrity-manifest.sh
#
# BUILD-TIME script (not run on boot). Run this once the base system
# is finished being built, against the finished root — it records a
# sha256 of each critical file into a manifest. That manifest is what
# boot-integrity-check.sh compares against on every subsequent boot,
# to catch corruption (a half-written file, bad sectors, a botched
# update) before the rest of boot continues.
#
# Usage: ./05-generate-integrity-manifest.sh /path/to/built/root
#
set -euo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    echo "Usage: $0 /path/to/built/root" >&2
    exit 1
fi

MANIFEST_DIR="$ROOT/etc/featheros"
MANIFEST="$MANIFEST_DIR/integrity-manifest"
mkdir -p "$MANIFEST_DIR"

# Paths to track, relative to $ROOT, split by severity:
#
# CRITICAL — boot genuinely can't continue safely without these.
# A failure here halts boot (see boot-integrity-check.sh /
# splash-feather.sh for how). Keep this list short and deliberate —
# only things that actually break the system if corrupted.
#
# WARN — worth flagging, but boot continues normally. Most things
# belong here.
CRITICAL_PATHS=(
    "bin/busybox"
    "sbin/init"
)

WARN_PATHS=(
    "etc/os-release"
    "usr/bin/featheros-splash.sh"
    "usr/bin/apk"
)

echo "Generating integrity manifest for: $ROOT"
: > "$MANIFEST"

record_paths() {
    local severity="$1"
    shift
    for rel_path in "$@"; do
        full_path="$ROOT/$rel_path"
        if [ -f "$full_path" ]; then
            hash=$(sha256sum "$full_path" | awk '{print $1}')
            echo "$severity $hash $rel_path" >> "$MANIFEST"
            echo "  recorded ($severity): $rel_path"
        else
            echo "  [SKIP] $rel_path — not found in built root (not built yet, or path needs updating)"
        fi
    done
}

record_paths "CRITICAL" "${CRITICAL_PATHS[@]}"
record_paths "WARN" "${WARN_PATHS[@]}"

echo
echo "Manifest written to $MANIFEST"
echo "$(wc -l < "$MANIFEST") entries recorded."
