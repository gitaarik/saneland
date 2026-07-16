#!/usr/bin/env bash
#
# Shared helpers for the hypr-* window-management scripts. Source it:
#
#   source "${HOME}/.local/bin/hypr-window-lib.sh"
#
# Holds the monitor/scale -> work-area computation that used to be
# copy-pasted across hypr-fill-work-area, hypr-toggle-maximize,
# hypr-center-window and hypr-max-on-open, plus the two geometry
# primitives those scripts apply (maximize, and apply-explicit-geometry).
#
# Not executable on its own — it only defines functions.

# Compute a monitor's usable work area. With no arg it uses the focused
# monitor; pass a numeric monitor id to target a specific one.
#
# PREFER hypr_work_area_for (below) when you have a window address. The
# focused *monitor* is cursor-driven here (input:follow_mouse=2 plus
# cursor:no_warps=true, see hyprland.conf), so it routinely disagrees with
# the focused *window's* monitor: focus a window on the other output via the
# taskbar or alt-tab and the cursor — hence the "focused" monitor — stays put.
# Sizing a window against the wrong monitor is how windows on a second output
# ended up wearing the laptop's work-area dimensions.
#
# Sets globals:
#   WORK_W, WORK_H  work-area size in logical px (monitor / scale, minus the
#                   reserved zones, e.g. the eww bar)
#   WORK_X, WORK_Y  work-area origin in Hyprland's GLOBAL logical coordinate
#                   space — the monitor's own position plus its reserved
#                   left/top zones.
#
# WORK_X/WORK_Y matter: Hyprland addresses every monitor in one global
# coordinate space, so movewindowpixel's origin is NOT the current monitor's
# top-left. Hardcoding 0 there silently means "the leftmost monitor", which
# teleported windows off a second output whenever they were maximized or
# snapped. Always offset an explicit position by WORK_X/WORK_Y.
#
# Returns 1 if no monitor could be resolved.
hypr_work_area() {
    local sel=${1:-} mon
    if [[ -n $sel ]]; then
        mon=$(hyprctl -j monitors | jq -c --argjson id "$sel" \
            '.[] | select(.id == $id)')
    else
        mon=$(hyprctl -j monitors | jq -c 'map(select(.focused))[0]')
    fi
    [[ -z $mon || $mon = "null" ]] && mon=$(hyprctl -j monitors | jq -c '.[0]')
    [[ -z $mon || $mon = "null" ]] && return 1

    local mw mh mon_name mon_x mon_y res_l res_t res_r res_b scale
    mw=$(      jq -r '.width'       <<<"$mon")
    mh=$(      jq -r '.height'      <<<"$mon")
    mon_name=$(jq -r '.name'        <<<"$mon")
    mon_x=$(   jq -r '.x'           <<<"$mon")
    mon_y=$(   jq -r '.y'           <<<"$mon")
    res_l=$(   jq -r '.reserved[0]' <<<"$mon")
    res_t=$(   jq -r '.reserved[1]' <<<"$mon")
    res_r=$(   jq -r '.reserved[2]' <<<"$mon")
    res_b=$(   jq -r '.reserved[3]' <<<"$mon")

    # wlr-randr preserves precise scale; hyprctl rounds to 2 decimals (1.57 for
    # a 1.5666667 panel, which is a ~4px error across 1504px — enough to leave
    # a sliver of desktop under a "maximized" window).
    #
    # NOTE: `--output NAME` does NOT filter wlr-randr's report — it selects an
    # output to *modify*, and with no modification flag wlr-randr just prints
    # every output anyway. So the scale must be parsed out of NAME's own block:
    # matching a bare `Scale:` line grabbed the FIRST output's scale, which on
    # multi-monitor meant every monitor was measured with the laptop's 1.5667
    # (the 4K TV came out 2451px wide instead of 3840). Output names start at
    # column 0; their properties are indented.
    scale=$(wlr-randr 2>/dev/null | awk -v name="$mon_name" '
        /^[^[:space:]]/ { cur = $1 }
        cur == name && $1 == "Scale:" { print $2; exit }
    ')
    [[ -z $scale ]] && scale=$(jq -r '.scale' <<<"$mon")

    # .x/.y and .reserved[] are already logical px; only .width/.height are
    # physical and need the scale divide.
    WORK_X=$(( mon_x + res_l ))
    WORK_Y=$(( mon_y + res_t ))
    WORK_W=$(awk -v w="$mw" -v s="$scale" -v l="$res_l" -v r="$res_r" \
        'BEGIN { printf "%d", (w / s) - l - r }')
    WORK_H=$(awk -v h="$mh" -v s="$scale" -v t="$res_t" -v b="$res_b" \
        'BEGIN { printf "%d", (h / s) - t - b }')
}

# The id of the monitor a window is on, or empty if the window is unknown.
hypr_window_monitor() {
    hyprctl -j clients 2>/dev/null \
        | jq -r --arg a "$1" '.[] | select(.address == $a) | .monitor' 2>/dev/null
}

# hypr_work_area for the monitor a specific WINDOW is on. This is what almost
# every caller wants — see the focused-monitor caveat on hypr_work_area.
# Falls back to the focused monitor if the window can't be resolved.
hypr_work_area_for() {
    local mon_id
    mon_id=$(hypr_window_monitor "$1")
    if [[ $mon_id =~ ^[0-9]+$ ]]; then
        hypr_work_area "$mon_id"
    else
        hypr_work_area
    fi
}

# Emit the --batch clauses for a window's "chrome" — the border, corner
# rounding, and hyprbars title bar, which are coupled into three looks:
#   max     borderless + square corners + NO title bar, for a full-screen
#           window (all pure noise there; rounding leaves gaps of desktop at
#           the corners)
#   snap    2px active border + default rounding + NO title bar, for an
#           edge-snapped half/quarter (a "tiled" window — no bar wanted)
#   normal  2px active border + default rounding + title bar, for a free-
#           floating sub-work-area window (dialogs, mod+c center, etc.)
# The title bar is toggled with a `nobar` window tag that the `hyprbars:no_bar`
# windowrule (config/hypr/hyprland.conf) keys off — max/snap add it, normal
# removes it. Prints the clauses (no trailing newline) so callers can splice
# them into an existing hyprctl --batch string; this is the single source of
# truth for the chrome every window-management script applies.
hypr_chrome() {
    local addr=$1 mode=$2 border rounding nobar
    case $mode in
        max)  border=0 rounding=0     nobar=+nobar ;;
        snap) border=3 rounding=unset nobar=+nobar ;;
        *)    border=3 rounding=unset nobar=-nobar ;;
    esac
    printf 'dispatch setprop address:%s border_size %s; dispatch setprop address:%s rounding %s; dispatch tagwindow %s address:%s' \
        "$addr" "$border" "$addr" "$rounding" "$nobar" "$addr"
}

# Maximize a window: fill ITS OWN monitor's work area and give it the
# borderless, square-cornered "max" chrome. This is what mod+m's maximize
# and the new-window fallback both want.
hypr_set_max() {
    local addr=$1
    hypr_work_area_for "$addr" || return 1
    hyprctl --batch \
        "dispatch resizewindowpixel exact ${WORK_W} ${WORK_H},address:${addr}; \
         dispatch movewindowpixel exact ${WORK_X} ${WORK_Y},address:${addr}; \
         $(hypr_chrome "$addr" max)" >/dev/null
}

# Apply an explicit geometry to a window, picking the chrome to match: a
# window that fills the work area (within a few px of scale rounding) gets
# the borderless, square-cornered "max" look like a real maximize; anything
# smaller gets the "normal" 2px-border + default-rounding look. This is the
# missing piece that left restored windows wearing a stray active-border
# around an otherwise-maximized frame.
#
# x/y are GLOBAL logical coordinates (see hypr_work_area) — callers holding a
# monitor-relative offset must add WORK_X/WORK_Y before calling.
hypr_apply_geom() {
    local addr=$1 w=$2 h=$3 x=$4 y=$5
    hypr_work_area_for "$addr" || return 1
    local mode=normal
    local dw=$(( w - WORK_W )) dh=$(( h - WORK_H ))
    (( ${dw#-} <= 3 && ${dh#-} <= 3 )) && mode=max
    hyprctl --batch \
        "dispatch resizewindowpixel exact ${w} ${h},address:${addr}; \
         dispatch movewindowpixel exact ${x} ${y},address:${addr}; \
         $(hypr_chrome "$addr" "$mode")" >/dev/null
}
