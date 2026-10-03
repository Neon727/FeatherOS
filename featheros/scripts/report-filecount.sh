#!/usr/bin/env bash
#
# report-filecount.sh
#
# Reports real file counts and disk usage for a built FeatherOS
# root, once one actually exists (headless or desktop variant).
# Replaces guesswork with an actual measurement.
#
# Usage: ./report-filecount.sh /path/to/built/root [variant-label]
#   e.g. ./report-filecount.sh /mnt/lfs "headless"
#
set -euo pipefail

ROOT="${1:-}"
LABEL="${2:-unlabeled}"

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    echo "Usage: $0 /path/to/built/root [variant-label]" >&2
    echo "Given path doesn't exist or wasn't provided: '$ROOT'" >&2
    exit 1
fi

echo "== FeatherOS file count report: $LABEL =="
echo "Root: $ROOT"
echo "Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo

TOTAL_FILES=$(find "$ROOT" -xdev -type f 2>/dev/null | wc -l)
TOTAL_DIRS=$(find "$ROOT" -xdev -type d 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$ROOT" 2>/dev/null | cut -f1)

echo "Total files: $TOTAL_FILES"
echo "Total dirs:  $TOTAL_DIRS"
echo "Total size:  ${TOTAL_SIZE:-unknown}"
echo

echo "== Breakdown by top-level directory =="
printf "%-20s %12s %10s\n" "DIRECTORY" "FILES" "SIZE"
for dir in "$ROOT"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    count=$(find "$dir" -xdev -type f 2>/dev/null | wc -l)
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    printf "%-20s %12s %10s\n" "$name" "$count" "${size:-?}"
done

echo
echo "== Kernel modules (if present) =="
MODULE_DIR="$ROOT/lib/modules"
if [ -d "$MODULE_DIR" ]; then
    MOD_COUNT=$(find "$MODULE_DIR" -name '*.ko*' 2>/dev/null | wc -l)
    echo "Kernel module files: $MOD_COUNT"
else
    echo "(no lib/modules found — kernel not installed into this root yet)"
fi

echo
echo "== Largest 10 files (often reveals what to trim — locales, docs, unused assets) =="
find "$ROOT" -xdev -type f -exec du -h {} + 2>/dev/null | sort -rh | head -n 10
