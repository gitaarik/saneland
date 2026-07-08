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
# monitor; pass a numeric monitor id to target a specific one (the open
# daemon needs the *new window's* monitor, which may not be focused yet).
#
# Sets globals:
#   WORK_W, WORK_H  work-area size in logical px (monitor / scale, minus
#                   the top+bottom reserved zones, e.g. waybar)
#   RES_TOP         top reserved zone in logical px (the area's y origin)
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

    local mw mh mon_name res_bottom scale
    mw=$(        jq -r '.width'       <<<"$mon")
    mh=$(        jq -r '.height'      <<<"$mon")
    mon_name=$(  jq -r '.name'        <<<"$mon")
    RES_TOP=$(   jq -r '.reserved[1]' <<<"$mon")
    res_bottom=$(jq -r '.reserved[3]' <<<"$mon")

    # wlr-randr preserves precise scale; hyprctl rounds to 2 decimals.
    scale=$(wlr-randr --output "$mon_name" 2>/dev/null \
        | awk '$1 == "Scale:" { print $2 }')
    [[ -z $scale ]] && scale=$(jq -r '.scale' <<<"$mon")

    WORK_W=$(awk -v w="$mw" -v s="$scale" 'BEGIN { printf "%d", w / s }')
    WORK_H=$(awk -v h="$mh" -v s="$scale" -v t="$RES_TOP" -v b="$res_bottom" \
        'BEGIN { printf "%d", (h / s) - t - b }')
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

# Maximize a window: fill the focused monitor's work area and give it the
# borderless, square-cornered "max" chrome. This is what mod+m's maximize
# and the new-window fallback both want.
hypr_set_max() {
    local addr=$1
    hypr_work_area || return 1
    hyprctl --batch \
        "dispatch resizewindowpixel exact ${WORK_W} ${WORK_H},address:${addr}; \
         dispatch movewindowpixel exact 0 ${RES_TOP},address:${addr}; \
         $(hypr_chrome "$addr" max)" >/dev/null
}

# Apply an explicit geometry to a window, picking the chrome to match: a
# window that fills the work area (within a few px of scale rounding) gets
# the borderless, square-cornered "max" look like a real maximize; anything
# smaller gets the "normal" 2px-border + default-rounding look. This is the
# missing piece that left restored windows wearing a stray active-border
# around an otherwise-maximized frame.
hypr_apply_geom() {
    local addr=$1 w=$2 h=$3 x=$4 y=$5
    hypr_work_area || return 1
    local mode=normal
    local dw=$(( w - WORK_W )) dh=$(( h - WORK_H ))
    (( ${dw#-} <= 3 && ${dh#-} <= 3 )) && mode=max
    hyprctl --batch \
        "dispatch resizewindowpixel exact ${w} ${h},address:${addr}; \
         dispatch movewindowpixel exact ${x} ${y},address:${addr}; \
         $(hypr_chrome "$addr" "$mode")" >/dev/null
}
