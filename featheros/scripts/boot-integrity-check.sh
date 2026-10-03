#!/usr/bin/env bash
#
# boot-integrity-check.sh
#
# Runs at boot, launched BY the splash (splash-feather.sh) as a
# background job, so checks happen concurrently with the spinning
# feather rather than as a separate screen before it. Reads the
# manifest from 05-generate-integrity-manifest.sh — each entry is
# tagged CRITICAL or WARN — and checks existence + sha256 match.
#
# Live results are appended to --status-file as it goes, one line
# per check, so the splash can render them in real time. A trailing
# "DONE <PASS|WARN|CRITICAL>" line marks completion with the worst
# severity seen.
#
# Also prints the same results to stdout (redirect this to a log
# file when launching in the background — the splash owns the
# console directly, see splash-feather.sh).
#
# Exit codes: 0 = all pass, 1 = warn-level failures only,
# 2 = at least one critical failure.
#
# Usage: ./boot-integrity-check.sh [root] [manifest-path] [--status-file PATH]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="/"
MANIFEST=""
STATUS_FILE=""

# --- argument parsing (simple positional + one flag) ---
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --status-file) STATUS_FILE="$2"; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
[ "${#args[@]}" -ge 1 ] && ROOT="${args[0]}"
[ "${#args[@]}" -ge 2 ] && MANIFEST="${args[1]}"
[ -z "$MANIFEST" ] && MANIFEST="$ROOT/etc/featheros/integrity-manifest"

source "$SCRIPT_DIR/lib/colors.sh"

status_append() {
    [ -n "$STATUS_FILE" ] && echo "$1" >> "$STATUS_FILE"
}

if [ -n "$STATUS_FILE" ]; then
    : > "$STATUS_FILE"
fi

if [ ! -f "$MANIFEST" ]; then
    echo "$(fail_tag) integrity manifest not found at $MANIFEST"
    status_append "MALFORMED CRITICAL (manifest missing: $MANIFEST)"
    status_append "DONE CRITICAL"
    exit 2
fi

WORST="PASS"       # PASS -> WARN -> CRITICAL, only ever escalates
CHECK_COUNT=0

echo "FeatherOS boot integrity check"
echo

while IFS= read -r line; do
    [ -z "$line" ] && continue
    severity=$(echo "$line" | awk '{print $1}')
    expected_hash=$(echo "$line" | awk '{print $2}')
    rel_path=$(echo "$line" | cut -d' ' -f3-)
    full_path="$ROOT/$rel_path"
    CHECK_COUNT=$((CHECK_COUNT + 1))

    if [ ! -f "$full_path" ]; then
        echo "$(fail_tag) [$severity] $rel_path (missing)"
        status_append "MALFORMED $severity $rel_path (missing)"
        [ "$severity" = "CRITICAL" ] && WORST="CRITICAL"
        [ "$severity" = "WARN" ] && [ "$WORST" = "PASS" ] && WORST="WARN"
        continue
    fi

    actual_hash=$(sha256sum "$full_path" 2>/dev/null | awk '{print $1}')
    if [ "$actual_hash" = "$expected_hash" ]; then
        echo "$(ok_tag) [$severity] $rel_path"
        status_append "OK $severity $rel_path"
    else
        echo "$(fail_tag) [$severity] $rel_path (checksum mismatch)"
        status_append "MALFORMED $severity $rel_path (checksum mismatch)"
        [ "$severity" = "CRITICAL" ] && WORST="CRITICAL"
        [ "$severity" = "WARN" ] && [ "$WORST" = "PASS" ] && WORST="WARN"
    fi
done < "$MANIFEST"

echo
case "$WORST" in
    PASS)     echo "$(ok_tag) all $CHECK_COUNT checks passed" ;;
    WARN)     echo "$(fail_tag) non-critical check(s) failed — boot continuing" ;;
    CRITICAL) echo "$(fail_tag) CRITICAL check(s) failed — boot should not continue" ;;
esac

status_append "DONE $WORST"

case "$WORST" in
    PASS) exit 0 ;;
    WARN) exit 1 ;;
    CRITICAL) exit 2 ;;
esac
