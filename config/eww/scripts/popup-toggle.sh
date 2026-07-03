#!/usr/bin/env bash
#
# Toggle an eww popup window, with close-on-outside-interaction.
#
# Usage: popup-toggle.sh <window-name>
#
# When opening, two close-triggers are armed; both funnel into
# popup-dismiss.sh so they're idempotent and safe to fire concurrently:
#
#   1. A Hyprland events-socket listener — closes on the first
#      `activewindow` event, which fires whenever focus shifts to a
#      different tiled window (mouse click that changes focus, or any
#      keyboard navigation).
#
#   2. A Hyprland `bindrn` on mouse:272 (release, non-consuming) — fires
#      on ANY left-click release, even when the focused window doesn't
#      change (e.g. clicking a single fullscreen window). The `n` flag
#      means the click still propagates to whatever's under the cursor,
#      so the user's click is not stolen. The bind invokes
#      popup-dismiss-if-outside.sh which checks the cursor against the
#      popup's layer-shell bounds, so clicks INSIDE the popup (mute
#      toggle, slider drag, etc.) don't also dismiss it.
#
# The bindrn is registered after a 0.4s delay so that the user's own
# initial open-click release doesn't immediately re-close the popup.
#
# Listener PID is stored per-window in $XDG_RUNTIME_DIR so multiple
# popups don't trample each other.

set -uo pipefail

window=${1:?missing window name}
pid_file=${XDG_RUNTIME_DIR:-/tmp}/eww-popup-listener-$window.pid
dismiss=$HOME/.config/eww/scripts/popup-dismiss.sh
dismiss_if_outside=$HOME/.config/eww/scripts/popup-dismiss-if-outside.sh

if eww active-windows 2>/dev/null | grep -q "^$window:"; then
  "$dismiss" "$window"
  exit 0
fi

# Clean switch: close any OTHER popup that's currently open before opening
# this one. Switching used to rely solely on the outgoing popup's
# click-outside mouse:272 bind — but that bind is armed 0.4s AFTER open
# (and, now that popups aren't focusable, opening one emits no
# `activewindow` for the old popup's listener to catch), so clicking a
# second icon in quick succession left the first popup up. Dismissing here
# makes the switch synchronous and timing-independent; the mouse:272 /
# activewindow dismissals now only handle clicks onto non-popup areas.
# Uses the live window list (not the open-popup var) as ground truth, so
# it also recovers if a prior race left more than one popup open.
while IFS= read -r other; do
  [[ -n $other && $other != "$window" ]] && "$dismiss" "$other"
done < <(eww active-windows 2>/dev/null | cut -d: -f1 | grep -- '-popup$')

eww open "$window"
# Surface the open popup as a reactive eww var so widgets can gate
# scroll-to-adjust behavior on "this control's popup is open".
eww update open-popup="$window" 2>/dev/null || true

# Per-popup open hooks. Start menu: clear any armed destructive-action
# state so the menu always opens on the normal power row, never a stale
# "Power off?" confirm left over from a previous open that was dismissed
# by clicking outside.
if [[ $window == start-popup ]]; then
    eww update start-confirm="" 2>/dev/null || true
fi

# Bluetooth: clear stale error markers from prior connect attempts so the
# popup opens with a clean slate. The state-script's next emit will
# reflect the cleared state.
if [[ $window == bluetooth-popup ]]; then
    bt_state_dir=${XDG_RUNTIME_DIR:-/tmp}/bluetooth-device-state
    for f in "$bt_state_dir"/*; do
        [[ -f $f && $(<"$f") == error ]] && rm -f "$f"
    done
    bt_pid_file=${XDG_RUNTIME_DIR:-/tmp}/eww-bluetooth-state.pid
    [[ -f $bt_pid_file ]] && kill -USR1 "$(<"$bt_pid_file")" 2>/dev/null
fi

if [[ $window == network-popup ]]; then
    net_state_dir=${XDG_RUNTIME_DIR:-/tmp}/network-wifi-state
    for f in "$net_state_dir"/*; do
        [[ -f $f && $(<"$f") == error ]] && rm -f "$f"
    done
    # Flag for network-state.sh so it knows to build the (expensive)
    # wifi network list. While the popup is closed the script skips
    # that query — `nmcli device wifi list` forces NM to surface fresh
    # scan data and is the dominant cost. Must touch BEFORE the SIGUSR1
    # so the immediate emit sees the flag.
    touch "${XDG_RUNTIME_DIR:-/tmp}/eww-network-popup-open"
    net_pid_file=${XDG_RUNTIME_DIR:-/tmp}/eww-network-state.pid
    [[ -f $net_pid_file ]] && kill -USR1 "$(<"$net_pid_file")" 2>/dev/null
fi

( sleep 0.4
  hyprctl keyword "bindrn" ", mouse:272, exec, $dismiss_if_outside $window" >/dev/null 2>&1
) &
disown

# Esc closes the popup. The window is `:focusable true`, so it holds the
# keyboard while open — this is the primary keyboard escape route (and a
# consuming `bind`, not bindrn, so Esc dismisses the popup rather than
# leaking through to the window that regains focus). Hyprland evaluates
# keybinds before delivering keys to the focused surface, so it fires even
# with the layer's keyboard grab. Registered immediately (unlike the mouse
# bind there's no open-click to race); popup-dismiss.sh unbinds it.
hyprctl keyword "bind" ", ESCAPE, exec, $dismiss $window" >/dev/null 2>&1

# Close action lives INSIDE the while loop, not after it. Reason: with
# `... | while ...; break`, the while subshell exits on break but ncat
# stays blocked reading from the socket. The bash pipeline only completes
# when ncat next writes (which only happens on the NEXT Hyprland event)
# — so a post-loop close would lag by one focus change. Inline + exit
# fires the dismiss the instant we match; the orphaned ncat reaps itself
# on its next write.
sock=${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock
{
  ncat -U "$sock" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      activewindow*)
        "$dismiss" "$window"
        exit 0
        ;;
    esac
  done
} &
echo $! > "$pid_file"
disown
