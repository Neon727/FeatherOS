#!/usr/bin/env bash
#
# lib/colors.sh
#
# Shared color codes for boot-time status output. Auto-detects
# whether the terminal actually supports color; falls back to plain
# text (just the [OK]/[MALFORMED] tags, no escape codes) if not —
# so this works whether or not the console supports ANSI color.
#
# Usage: source "$(dirname "$0")/lib/colors.sh"
#   Then use: ok_tag, fail_tag  — e.g. echo "$(ok_tag) kernel modules"
#

_supports_color() {
    # Only color if stdout is an actual terminal AND it claims to
    # support at least 8 colors. Covers piping to a logfile, a
    # dumb serial console, etc. gracefully.
    if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
        local n
        n=$(tput colors 2>/dev/null || echo 0)
        [ "${n:-0}" -ge 8 ] 2>/dev/null
        return $?
    fi
    return 1
}

if _supports_color; then
    COLOR_RED=$(tput setaf 1)
    COLOR_GREEN=$(tput setaf 2)
    COLOR_RESET=$(tput sgr0)
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_RESET=""
fi

ok_tag() {
    printf '%s[OK]%s' "$COLOR_GREEN" "$COLOR_RESET"
}

fail_tag() {
    printf '%s[MALFORMED]%s' "$COLOR_RED" "$COLOR_RESET"
}
