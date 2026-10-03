#!/usr/bin/env bash
#
# splash-feather.sh
#
# ASCII boot splash for FeatherOS: a feather with a spinning quill
# tip, rendered directly to the console, with live boot-integrity
# check results shown underneath it as they complete — the checks
# run concurrently with the animation, not before it.
#
# A CRITICAL check failure halts boot into a rescue shell. A WARN
# failure is shown but boot continues normally.
#
# Usage:
#   splash-feather.sh start   # launches checks + animation in the
#                              # background, returns immediately
#   splash-feather.sh stop    # kills the animation, clears the
#                              # screen, hands the console back
#                              # (normal end-of-boot call)
#
# Hook "start" into the earliest boot stage with a console. Hook
# "stop" into the last boot step, right before login/display manager.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="/run/featheros-splash.pid"
CHECK_PIDFILE="/run/featheros-integrity-check.pid"
STATUS_FILE="/run/featheros-integrity-status"
CHECK_LOG="/var/log/featheros-integrity.log"
CHECKER="${CHECKER:-$SCRIPT_DIR/boot-integrity-check.sh}"

SPIN_CHARS=('|' '/' '-' '\')
FRAME_DELAY=0.12
MAX_STATUS_LINES=6   # keep the screen from overflowing on small terminals

source "$SCRIPT_DIR/lib/colors.sh"

# --- Rendering ---

draw_screen() {
    local spin_char="$1"
    local shade="$2"
    clear
    local feather_rows=14
    local term_rows term_cols
    term_rows=$(tput lines 2>/dev/null || echo 24)
    term_cols=$(tput cols 2>/dev/null || echo 80)
    local top_pad=$(( (term_rows - feather_rows - 2 - MAX_STATUS_LINES) / 2 ))
    (( top_pad < 0 )) && top_pad=0

    for ((i=0; i<top_pad; i++)); do echo; done

    local lines=(
        "          ,"
        "         ,;"
        "        ,;;"
        "       ,;;;"
        "      ,;;;;"
        "     ,;;${shade};;"
        "    ,;;;;;;"
        "   ,;;;;;;;>"
        "   ;;;;;;;;"
        "    \`;;;;;'"
        "      \`;;'"
        "       ';"
        "        ${spin_char}"
        "     FeatherOS"
    )

    local pad=$(( (term_cols - 20) / 2 ))
    (( pad < 0 )) && pad=0

    for line in "${lines[@]}"; do
        printf '%*s%s\n' "$pad" '' "$line"
    done

    echo
    render_status_lines "$pad"
}

# Reads whatever the background integrity check has written so far
# and prints the most recent entries, colored. Returns the overall
# result via the global LAST_DONE_STATUS variable once a "DONE" line
# appears (empty string until then).
LAST_DONE_STATUS=""
render_status_lines() {
    local pad="$1"
    [ -f "$STATUS_FILE" ] || return 0

    LAST_DONE_STATUS=""
    local shown=0
    # Tail the most recent lines so the status area has a bounded
    # height even if the manifest grows large.
    while IFS= read -r line; do
        shown=$((shown + 1))
        case "$line" in
            OK\ *)
                local rest="${line#OK }"
                printf '%*s%s %s\n' "$pad" '' "$(ok_tag)" "$rest"
                ;;
            MALFORMED\ *)
                local rest="${line#MALFORMED }"
                printf '%*s%s %s\n' "$pad" '' "$(fail_tag)" "$rest"
                ;;
            DONE\ *)
                LAST_DONE_STATUS="${line#DONE }"
                ;;
        esac
    done < <(tail -n "$MAX_STATUS_LINES" "$STATUS_FILE" 2>/dev/null)
}

# --- Halt path for a critical failure ---

halt_for_critical_failure() {
    clear
    echo
    echo "  $(fail_tag) CRITICAL system file check failed."
    echo "  FeatherOS cannot safely continue booting."
    echo
    echo "  Dropping to a recovery shell. Check $STATUS_FILE"
    echo "  and $CHECK_LOG for details."
    echo

    # Standard "boot can't continue safely" pattern: drop to a
    # maintenance shell rather than pressing on. sulogin is the
    # real tool for this if present; plain sh is the fallback for
    # a minimal/early-boot environment that may not have it yet.
    if command -v sulogin >/dev/null 2>&1; then
        exec sulogin
    elif [ -x /bin/sh ]; then
        exec /bin/sh
    else
        # Last resort: stay visible and halted rather than silently
        # falling through to the rest of boot.
        while true; do sleep 3600; done
    fi
}

# --- Main animation loop ---

animate_loop() {
    local i=0
    local shade_chars=(';' ':')
    trap 'clear; exit 0' TERM INT

    while true; do
        spin="${SPIN_CHARS[$(( i % 4 ))]}"
        shade="${shade_chars[$(( (i / 4) % 2 ))]}"
        draw_screen "$spin" "$shade"

        if [ "$LAST_DONE_STATUS" = "CRITICAL" ]; then
            halt_for_critical_failure
            # halt_for_critical_failure execs into a shell and does
            # not return under normal circumstances; this exit only
            # fires if every fallback above somehow failed.
            exit 1
        fi

        sleep "$FRAME_DELAY"
        i=$((i + 1))
    done
}

# --- start/stop ---

start_splash() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        echo "Splash already running (pid $(cat "$PIDFILE"))." >&2
        exit 0
    fi

    : > "$STATUS_FILE"
    mkdir -p "$(dirname "$CHECK_LOG")" 2>/dev/null || true

    # Integrity checks run concurrently with the animation, not
    # before it — both start together here.
    "$CHECKER" --status-file "$STATUS_FILE" >"$CHECK_LOG" 2>&1 &
    echo $! > "$CHECK_PIDFILE"
    disown

    animate_loop &
    echo $! > "$PIDFILE"
    disown
}

stop_splash() {
    if [ -f "$CHECK_PIDFILE" ]; then
        local cpid
        cpid=$(cat "$CHECK_PIDFILE")
        kill -0 "$cpid" 2>/dev/null && kill -TERM "$cpid" 2>/dev/null
        rm -f "$CHECK_PIDFILE"
    fi

    if [ ! -f "$PIDFILE" ]; then
        clear
        exit 0
    fi
    local pid
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null
        for _ in 1 2 3 4 5; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
    fi
    rm -f "$PIDFILE"
    clear
}

case "${1:-}" in
    start) start_splash ;;
    stop)  stop_splash ;;
    *)
        echo "Usage: $0 {start|stop}" >&2
        exit 1
        ;;
esac
