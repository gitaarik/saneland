#!/usr/bin/env bash
#
# Dismiss eww popups on a click OUTSIDE them. Bound permanently in
# hyprland.conf:
#
#   bindrn = , mouse:272, exec, ~/.config/eww/scripts/popup-dismiss-if-outside.sh
#
# Usage:
#   popup-dismiss-if-outside.sh                 whichever popup is open
#   popup-dismiss-if-outside.sh <window-name>   that popup only
#
# `bindrn` is release + non-consuming: the click still reaches whatever is under
# the cursor, so dismissing a menu doesn't swallow the click that did it.
#
# This runs on EVERY left-click release in the session, so the order of the
# checks is the design. Cheapest first:
#
#   1. marker file        ~1ms   — no popup can be open without it
#   2. eww active-windows ~14ms  — the authority on what is open
#   3. cursor vs layers   ~73ms  — only worth asking once we know there IS a popup
#
# It used to be bound only while a popup was open, which meant arming and
# unbinding a global keybind from concurrent short-lived scripts — the source of
# every stuck-popup bug in this system. Being always bound costs step 1 per click
# and removes the entire class. See the header of popup-dismiss.sh.

set -uo pipefail
# shellcheck source=/dev/null
source "$HOME/.config/eww/scripts/popup-lib.sh"

window=${1:-}

popups_possible || exit 0

# The marker over-approximates, so confirm with eww before paying for the cursor
# test. Finding nothing here also clears the marker, which is how a stale one
# heals — an eww daemon restart (a monitor hotplug does one, see ensure_daemon in
# eww-bars.sh) takes every popup down without anything running a dismiss.
if [[ -z $(open_popups) ]]; then
  clear_marker_if_empty
  exit 0
fi

# `hyprctl cursorpos` prints "X, Y". Strip the comma, read two ints.
read -r cx cy <<< "$(hyprctl cursorpos | tr -d ',')"

# Overlay-level (level 3) layer-shell surfaces are popups (the bar lives
# at level 2 = "top"). If the cursor is inside any overlay surface on any
# monitor, treat the click as "inside the popup" and skip dismiss.
#
# Pass the python script via -c (not via `- <<HEREDOC`) so that hyprctl's
# JSON reaches sys.stdin via the pipe — `python3 - <<HEREDOC` would use
# the heredoc AS the script and leave sys.stdin at EOF.
inside=$(hyprctl layers -j | python3 -c '
import json, sys
cx, cy = int(sys.argv[1]), int(sys.argv[2])
data = json.load(sys.stdin)
for mon, info in data.items():
    for surface in info.get("levels", {}).get("3", []):
        x, y, w, h = surface["x"], surface["y"], surface["w"], surface["h"]
        if x <= cx < x + w and y <= cy < y + h:
            print("yes"); sys.exit(0)
' "$cx" "$cy")

if [[ -n $inside ]]; then
  popup_log "click at $cx,$cy is inside a popup — keeping it open"
  exit 0
fi

popup_log "click at $cx,$cy is outside"

# Everything past the cursor test is popup-dismiss.sh's job, so the rules about
# WHICH popups go — and how young is too young — live in one place and can be
# tested without a mouse.
dismiss=$HOME/.config/eww/scripts/popup-dismiss.sh
if [[ -n $window ]]; then
  "$dismiss" "$window"
else
  "$dismiss" --settled
fi
