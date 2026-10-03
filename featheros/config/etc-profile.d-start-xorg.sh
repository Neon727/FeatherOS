#!/bin/sh
# /etc/profile.d/start-xorg.sh (install to this path on the real system)
#
# Auto-starts Xorg + i3 right after login, without running a full
# display manager daemon in the background the whole time. This file
# gets sourced automatically by login shells via /etc/profile.
#
# Only triggers when:
#   - logging in on tty1 specifically (the first virtual console) —
#     so logging into tty2+ (e.g. a second session, SSH-like local
#     use) doesn't also try to launch a GUI
#   - $DISPLAY isn't already set — so this doesn't fire again if
#     you're already inside an X session somehow (e.g. a terminal
#     spawned from within i3 itself also sources /etc/profile)
#
# Uses exec rather than just calling startx, so when X exits (i3
# quit, crash, etc.) you land back at a fresh login prompt rather
# than an orphaned shell still sitting inside the old login session.

if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
