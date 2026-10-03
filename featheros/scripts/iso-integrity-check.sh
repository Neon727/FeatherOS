#!/usr/bin/env bash
#
# iso-integrity-check.sh
#
# Runs during the boot sequence of the FeatherOS install/live media
# (hooked into the ISO's own boot menu / early init — before the
# installer or splash takes over), checking the booted media against
# the checksum embedded by 06-embed-iso-checksum.sh. Uses checkisomd5
# (from Alpine's isomd5sum package) to do the actual verification.
#
# On a match: prints [OK] and continues boot automatically, no
# prompt needed.
#
# On a mismatch: prints a [WARNING], explains the risk, and requires
# an explicit y/n before continuing — since a modified ISO could be
# anything from a corrupted download to something actively malicious.
#
# Usage: ./iso-integrity-check.sh [device-or-iso-path]
#   Defaults to /dev/sr0 (typical optical/USB boot device node);
#   override if your boot media shows up elsewhere.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-/dev/sr0}"

source "$SCRIPT_DIR/lib/colors.sh"

# Runs the actual check and returns checkisomd5's exit code:
# 0 = match, nonzero = mismatch or tool/media problem. Kept as its
# own function so the decision logic below can be tested
# independently of having real boot media / the real tool present.
run_checksum_check() {
    if ! command -v checkisomd5 >/dev/null 2>&1; then
        echo "checkisomd5 not found — cannot verify media integrity." >&2
        return 2
    fi
    checkisomd5 "$TARGET"
}

# Takes the check's exit code and decides what to show / whether to
# continue. Returns 0 if boot should continue, 1 if it should not
# (caller decides what "not continuing" means in context — abort,
# drop to a shell, etc.)
handle_result() {
    local result="$1"

    if [ "$result" -eq 0 ]; then
        echo "$(ok_tag) ISO integrity check passed — media matches expected checksum."
        return 0
    fi

    echo
    echo "$(fail_tag) The hash on this iso does not match the internal hash."
    echo
    echo "Are you sure you want to proceed? Using a modified iso may"
    echo "contain malicious code and may leave your computer inoperable. [y/n]"

    local answer
    read -r answer
    case "$answer" in
        y|Y) echo "Continuing at your own risk."; return 0 ;;
        *)   echo "Boot aborted."; return 1 ;;
    esac
}

echo "FeatherOS media integrity check: $TARGET"
run_checksum_check
result=$?
handle_result "$result"
exit $?
