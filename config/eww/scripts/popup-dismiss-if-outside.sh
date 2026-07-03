#!/usr/bin/env bash
#
# Dismiss an eww popup window ONLY if the cursor is outside of any open
# overlay layer-shell surface (i.e. the popup itself).
#
# Used as the action for the Hyprland `bindrn` mouse:272 hook armed by
# popup-toggle.sh, so that clicks INSIDE the popup (toggling mute,
# dragging the volume slider, etc.) don't also dismiss it.
#
# Usage: popup-dismiss-if-outside.sh <window-name>

set -uo pipefail

window=${1:?missing window name}

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

if [[ -z $inside ]]; then
  "$HOME"/.config/eww/scripts/popup-dismiss.sh "$window"
fi
