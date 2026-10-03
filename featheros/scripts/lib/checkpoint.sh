#!/usr/bin/env bash
#
# lib/checkpoint.sh
#
# Reusable "save state" system for long-running build stages. Any
# stage script sources this and wraps each build step in run_step —
# completed steps are skipped on re-run, so a crash, a typo, or
# running out of disk mid-build doesn't mean starting over.
#
# Usage in a stage script:
#   source "$(dirname "$0")/lib/checkpoint.sh"
#   run_step "binutils-pass1" build_binutils_pass1
#   run_step "gcc-pass1"      build_gcc_pass1
#
# State lives in $STATE_DIR (default: $LFS_ROOT/.featheros-state),
# one empty marker file per completed step — plain files on purpose,
# so you can inspect/delete them by hand if needed, no special tool
# required to read the state.
#

STATE_DIR="${STATE_DIR:-${LFS_ROOT:-/mnt/lfs}/.featheros-state}"
mkdir -p "$STATE_DIR" 2>/dev/null || true

step_done() {
    [ -f "$STATE_DIR/$1.done" ]
}

mark_step_done() {
    touch "$STATE_DIR/$1.done"
}

# run_step <name> <command...>
# Runs <command...> unless <name> is already marked done. On success,
# marks it done. On failure, stops the whole script immediately —
# re-running the stage script later picks up right after the last
# completed step.
run_step() {
    local step_name="$1"
    shift

    if step_done "$step_name"; then
        echo "[SKIP] $step_name (already completed — rm $STATE_DIR/$step_name.done to redo)"
        return 0
    fi

    echo "[RUN ] $step_name"
    local start_ts end_ts
    start_ts=$(date +%s)

    if "$@"; then
        mark_step_done "$step_name"
        end_ts=$(date +%s)
        echo "[DONE] $step_name ($(( end_ts - start_ts ))s)"
    else
        echo "[FAIL] $step_name" >&2
        echo "Build stopped here. Fix the issue above, then re-run this" >&2
        echo "script — every step before this one will be skipped" >&2
        echo "automatically, so you resume right where it broke." >&2
        exit 1
    fi
}

# reset_steps            — clears ALL checkpoint state for this stage
# reset_steps step1 step2 — clears just those steps, to redo them
#                            (and everything after them, since later
#                            steps may depend on them — rerun the
#                            stage script after resetting)
reset_steps() {
    if [ "$#" -eq 0 ]; then
        rm -rf "$STATE_DIR"
        mkdir -p "$STATE_DIR"
        echo "All checkpoint state cleared for $STATE_DIR"
    else
        for s in "$@"; do
            rm -f "$STATE_DIR/$s.done"
            echo "Cleared checkpoint: $s"
        done
    fi
}

list_steps() {
    echo "State dir: $STATE_DIR"
    echo "Completed steps:"
    if [ -d "$STATE_DIR" ] && [ -n "$(ls -A "$STATE_DIR" 2>/dev/null)" ]; then
        for f in "$STATE_DIR"/*.done; do
            [ -e "$f" ] || continue
            echo "  - $(basename "$f" .done)"
        done
    else
        echo "  (none yet)"
    fi
}
