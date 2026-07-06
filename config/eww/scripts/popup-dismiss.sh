#!/usr/bin/env bash
#
# Dismiss an eww popup window: close it, unbind the temporary Hyprland
# mouse:272 and Escape keybinds, and kill the per-window activewindow
# listener.
#
# Usage: popup-dismiss.sh <window-name>
#
# Called from:
#   - popup-toggle.sh's "close" branch (user re-clicks the trigger widget)
#   - app-specific pick scripts (e.g. audio-set-default.sh closes after
#     setting the default sink/source)
#   - the per-window activewindow listener (focus change to another window)
#   - Hyprland's bindrn for mouse:272 (any left-click while popup is open)
#
# Idempotent: safe to invoke multiple times in quick succession.
#
# Caveat: `hyprctl keyword unbind , mouse:272` removes one matching bind
# by key, not by dispatcher args. If two popups were open simultaneously,
# the unbind would leave the other popup's bind alive. In practice only
# one popup can be open at a time, so this isn't an issue.

set -uo pipefail

window=${1:?missing window name}

eww close "$window" 2>/dev/null || true
# Clear the open-popup gate only if we're the popup that owns it —
# avoids racing a different popup that just opened (rare but possible
# if dismiss is called twice in quick succession).
if [[ $(eww get open-popup 2>/dev/null) == "$window" ]]; then
  eww update open-popup="" 2>/dev/null || true
fi
hyprctl keyword "unbind" ", mouse:272" 2>/dev/null || true
# Drop the Esc-to-dismiss bind armed by popup-toggle.sh so Escape returns
# to whatever it normally does once the popup is gone.
hyprctl keyword "unbind" ", ESCAPE" 2>/dev/null || true

# Per-popup close hooks. Network: drop the popup-open flag so
# network-state.sh stops building the wifi list.
case $window in
    network-popup)
        rm -f "${XDG_RUNTIME_DIR:-/tmp}/eww-network-popup-open"
        # Kick the script so it re-emits with networks:[] right away
        # (instead of waiting for the next dbus event / poll tick to
        # notice the flag is gone).
        net_pid_file=${XDG_RUNTIME_DIR:-/tmp}/eww-network-state.pid
        [[ -f $net_pid_file ]] && kill -USR1 "$(<"$net_pid_file")" 2>/dev/null
        ;;
    start-popup)
        # The "All apps" pop-out is a companion window of the start menu —
        # close it too and reset its reveal state so it can't linger after
        # the menu is gone.
        eww close start-apps-popup 2>/dev/null || true
        eww update start-apps-open=false 2>/dev/null || true
        ;;
esac

pid_file=${XDG_RUNTIME_DIR:-/tmp}/eww-popup-listener-$window.pid
if [[ -f $pid_file ]]; then
  kill "$(<"$pid_file")" 2>/dev/null || true
  rm -f "$pid_file"
fi
