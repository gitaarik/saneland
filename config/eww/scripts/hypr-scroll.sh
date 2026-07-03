#!/usr/bin/env bash
#
# Scroll-wheel handlers for the bar's tags + taskbar widgets.
#
#   hypr-scroll.sh workspace up|down   # focus prev/next existing workspace
#   hypr-scroll.sh window    up|down   # cycle focus through windows on the
#                                      # active workspace
#
# Wired from eww :onscroll, which substitutes `{}` with `up` / `down`.
# `workspace e±1` (vs plain `±1`) skips empty workspaces — matches the
# fact that the tag widget hides empty/unfocused tags anyway, so the
# scroll stays in sync with what the user can see.
#
# Debounce: high-resolution / hyper-scroll mice emit many sub-events
# per physical detent, and eww fires :onscroll on every one — without
# a cooldown, a single notch jumps several workspaces.
#
# Leading-edge with extended lockout: fire on the first event of a
# burst, then suppress everything until the burst goes quiet for
# COOLDOWN_MS. Crucially, `last` is updated on EVERY event (not just
# fires), so a noisy detent that keeps emitting past COOLDOWN_MS still
# only counts once — each sub-event pushes the lockout forward.
# Tradeoff: intentional rapid scrolls (<200ms apart) get throttled, but
# in practice that's rare for workspace/window cycling.

set -uo pipefail

target=${1:?missing target}
direction=${2:?missing direction}

COOLDOWN_MS=200
state_dir=${XDG_RUNTIME_DIR:-/tmp}
state_file=$state_dir/hypr-scroll-$target.last

now=$(date +%s%3N)
last=$(cat "$state_file" 2>/dev/null || echo 0)
echo "$now" > "$state_file"

# Suppress the bar's hover glow while scroll-switching so it doesn't flash back
# on every step. Runs on EVERY event (before the cooldown gate) so the whole
# burst keeps the flag set; a per-event debounced resetter clears it once
# scrolling goes quiet for HOVER_QUIET_S. The shared token is this event's
# timestamp, so only the last event of the burst still matches and clears it.
hover_tok=$state_dir/hypr-scroll-hover.tok
HOVER_QUIET_S=0.6
echo "$now" > "$hover_tok"
(
  eww update scroll-switching=true
  sleep "$HOVER_QUIET_S"
  [[ "$(cat "$hover_tok" 2>/dev/null)" == "$now" ]] && eww update scroll-switching=false
) >/dev/null 2>&1 &

if (( now - last < COOLDOWN_MS )); then
  exit 0
fi

# Window cycling reuses hypr-cycle-maximize (also bound to mod+Tab /
# mod+Shift+Tab), which walks the workspace's windows in the taskbar's
# order. Hyprland's built-in `cyclenext` follows z-order, which the
# raise-focused daemon keeps shuffling — unpredictable with 3+ windows.
case "$target:$direction" in
  workspace:up)   hyprctl dispatch workspace e-1 ;;
  workspace:down) hyprctl dispatch workspace e+1 ;;
  window:up)      ~/.local/bin/hypr-cycle-maximize prev ;;
  window:down)    ~/.local/bin/hypr-cycle-maximize next ;;
  *) echo "hypr-scroll: unknown '$target/$direction'" >&2; exit 1 ;;
esac
