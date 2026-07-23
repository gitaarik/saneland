#!/usr/bin/env bash
#
# Scroll-wheel handlers for the bar's tags + taskbar widgets.
#
#   hypr-scroll.sh workspace up|down   # focus prev/next existing workspace
#   hypr-scroll.sh window    up|down   # cycle focus through windows on the
#                                      # active workspace
#
# Wired from eww :onscroll, which substitutes `{}` with `up` / `down`.
# Workspace scrolling cycles ONLY within the focused screen's own 12-workspace
# block (laptop 1-12, external 13-24), through its non-empty workspaces — so it
# matches the tags that screen shows and never jumps to another monitor's
# range. (A global `workspace e±1` would wrap into the other screen's block.)
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
case "$target" in
  workspace)
    # The focused (cursor) monitor's offset and current workspace. offset =
    # rank among monitors sorted by id, times 12 — same mapping as the bar and
    # hypr-workspace.
    read -r off cur < <(hyprctl -j monitors | jq -r '
        sort_by(.id) as $s
        | ($s | map(select(.focused))[0]) as $m
        | "\(([$s[].id] | index($m.id)) * 12) \($m.activeWorkspace.id)"')
    # Ring = this block's non-empty workspaces (+ the current one), sorted. Cycle
    # within it; up = previous, down = next, with wrap.
    mapfile -t ring < <(hyprctl -j workspaces | jq -r --argjson off "${off:-0}" --argjson cur "${cur:-0}" '
        ([ .[] | select(.id > $off and .id <= ($off + 12) and .windows > 0) | .id ] + [$cur])
        | unique | .[]')
    (( ${#ring[@]} > 1 )) || exit 0
    idx=0; for i in "${!ring[@]}"; do [[ ${ring[i]} == "$cur" ]] && idx=$i; done
    if [[ $direction == up ]]; then
        hyprctl dispatch workspace "${ring[$(( (idx - 1 + ${#ring[@]}) % ${#ring[@]} ))]}"
    else
        hyprctl dispatch workspace "${ring[$(( (idx + 1) % ${#ring[@]} ))]}"
    fi
    ;;
  window)
    case "$direction" in
      up)   ~/.local/bin/hypr-cycle-maximize prev ;;
      down) ~/.local/bin/hypr-cycle-maximize next ;;
      *) echo "hypr-scroll: unknown direction '$direction'" >&2; exit 1 ;;
    esac
    ;;
  *) echo "hypr-scroll: unknown target '$target'" >&2; exit 1 ;;
esac
