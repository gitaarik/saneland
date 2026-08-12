#!/usr/bin/env bash
#
# Toggle an eww popup window, with close-on-outside-interaction.
#
# Usage: popup-toggle.sh <window-name>
#
# Three things close a popup, all of them funnelling into popup-dismiss.sh so
# they are idempotent and safe to fire concurrently:
#
#   1. A Hyprland `bindrn` on mouse:272 (release, non-consuming) — fires on ANY
#      left-click release, even when the focused window doesn't change (e.g.
#      clicking a single fullscreen window). The `n` flag means the click still
#      propagates to whatever's under the cursor, so the user's click is not
#      stolen. It runs popup-dismiss-if-outside.sh, which checks the cursor
#      against the popup's layer-shell bounds so clicks INSIDE the popup (mute
#      toggle, slider drag) don't dismiss it.
#
#   2. A Hyprland bind on Escape, running popup-dismiss.sh --if-open.
#
#   3. A Hyprland events-socket listener — closes on the first `activewindow`
#      event, which fires whenever focus shifts to a different tiled window.
#
# THIS SCRIPT ARMS NOTHING. (1) and (2) are registered once, permanently, in
# hyprland.conf; they cost ~1ms per click when no popup is open and are never
# touched again. They used to be armed here on open and unbound on close, which
# is the same thing as keeping global compositor state in sync with per-window
# state from concurrent short-lived scripts — the source of every stuck-popup
# bug this system has had. See the header of popup-dismiss.sh.
#
# Only (3) is per-window, because it is a process this script owns and can kill;
# its PID is stored per-window in $XDG_RUNTIME_DIR so multiple popups don't
# trample each other.

set -uo pipefail
# shellcheck source=/dev/null
source "$HOME/.config/eww/scripts/popup-lib.sh"

window=${1:?missing window name}
pid_file=$runtime/eww-popup-listener-$window.pid
dismiss=$HOME/.config/eww/scripts/popup-dismiss.sh

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
done < <(eww active-windows 2>/dev/null | cut -d: -f1 | grep -- '-popup$' | grep -vx 'start-apps-popup')

# Open the popup on the monitor the cursor is on, so clicking any screen's bar
# pops up on THAT screen. eww's --screen is a GDK monitor index = the monitor's
# position when Hyprland's outputs are sorted by id (matches GDK's order). We
# find the cursor's monitor by its logical bounds: .x/.y are already logical,
# .width/.height are physical so divide by .scale. Falls back to 0 on any
# failure — which is also the only valid index on a single monitor, so this is
# a no-op there and needs no guarding.
read -r _cx _cy <<< "$(hyprctl cursorpos 2>/dev/null | tr -d ',')"
screen=$(hyprctl monitors -j | python3 -c '
import json, sys
try:
    cx, cy = int(sys.argv[1]), int(sys.argv[2])
except (IndexError, ValueError):
    print(0); sys.exit(0)
for idx, m in enumerate(sorted(json.load(sys.stdin), key=lambda m: m["id"])):
    w, h = m["width"] / m["scale"], m["height"] / m["scale"]
    if m["x"] <= cx < m["x"] + w and m["y"] <= cy < m["y"] + h:
        print(idx); sys.exit(0)
print(0)
' "$_cx" "$_cy" 2>/dev/null)
screen=${screen:-0}

# --no-daemonize: if the daemon can't be reached, fail — do NOT let eww fork a
# second one. `open` is the only subcommand that auto-starts a server, and the
# daemon it starts inherits THIS script's command line, so the rival is invisible
# to anything looking for a process called `eww daemon` and owns a full set of
# bars that no `eww close` can reach (see count_daemons in eww-bars.sh). A popup
# that doesn't open on a wedged daemon is a click to repeat; a rogue daemon is
# doubled bars until logout.
#
# Raise the marker BEFORE opening, never after. It is what the permanently-bound
# click and Escape handlers test first, and being early can only cost a wasted
# check that clears itself — being late would mean a popup on screen that those
# handlers skip straight past. See popup-lib.sh.
mark_popups_possible
trim_popup_log

# Bail out if it didn't open, rather than setting up close-triggers for a popup
# that isn't there. The marker stays behind, which is harmless: the next click
# checks eww, finds nothing open, and clears it.
if ! eww --no-daemonize open "$window" --screen "$screen"; then
  echo "popup-toggle.sh: $window did not open" >&2
  popup_log "FAILED to open $window"
  exit 1
fi
popup_log "opened $window on screen $screen"
# Stamp when it opened, in nanoseconds, so a --settled dismiss can tell that the
# click it is handling is the one that opened this popup. popup-dismiss.sh
# removes the stamp when it closes the window.
stamp_popup "$window"
# Surface the open popup as a reactive eww var so widgets can gate
# scroll-to-adjust behavior on "this control's popup is open".
eww update open-popup="$window" 2>/dev/null || true

# Per-popup open hooks. Start menu: clear any armed destructive-action
# state so the menu always opens on the normal power row, never a stale
# "Power off?" confirm left over from a previous open that was dismissed
# by clicking outside.
if [[ $window == start-popup ]]; then
    eww update start-confirm="" 2>/dev/null || true
    # Refresh the categorized "Browse apps" data (cheap: served from cache
    # unless an application dir changed) and preselect the first category for
    # the right pane once the flyout is expanded. Run DETACHED so a slow
    # rebuild — an app dir changed, forcing a full .desktop rescan — doesn't
    # block the menu from opening or the dismiss binds below from arming. While
    # start-apps.categories is still empty the flyout shows a "Loading apps…"
    # line (see start-apps-panel); this update fills it in when the scan lands.
    # The cached no-change path returns in milliseconds, well within the
    # Browse-apps hover-intent delay, so that line never actually flashes then.
    ( apps_json=$("$HOME/.config/eww/scripts/start-apps.sh" 2>/dev/null)
      if [[ -n $apps_json ]]; then
          first_cat=$(printf '%s' "$apps_json" | python3 -c \
              'import json,sys; c=json.load(sys.stdin)["categories"]; print(c[0] if c else "")')
          eww update start-apps="$apps_json" 2>/dev/null || true
          eww update start-apps-cat="$first_cat" 2>/dev/null || true
      fi ) &
    disown
    # Reset the flyout so the menu always opens collapsed.
    eww update start-apps-open=false 2>/dev/null || true
    # NOTE: the companion window (start-apps-popup) is opened at the very
    # END of this script, not here — see the deferred `eww open` below.
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

# Open the start menu's "Browse apps" flyout companion window, collapsed
# (its content keys on start-apps-open). It's mapped once and closed with
# the menu (popup-dismiss.sh) — not hover-toggled — so it never churns into
# a ghost surface.
#
# Deferred to the very end and DETACHED on purpose. `eww open` issued
# synchronously from inside eww's own button-onclick handler deadlocks and
# never returns; when this ran mid-hook it stalled the script before it
# armed the Esc / mouse:272 / activewindow dismiss routes, leaving the start
# menu impossible to close by Escape or click-outside. Backgrounding it lets
# the script finish arming those binds and return — eww then processes the
# open once its onclick handler is free.
if [[ $window == start-popup ]]; then
    # --no-daemonize for the same reason as the open above — doubly so here,
    # where the deadlock this defers around is itself a moment of the daemon
    # not answering, which is exactly when eww would fork the rival.
    eww --no-daemonize open start-apps-popup --screen "$screen" >/dev/null 2>&1 &
    disown
fi
