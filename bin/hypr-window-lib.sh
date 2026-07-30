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

# ---------------------------------------------------------------------------
# Auto-maximize policy
# ---------------------------------------------------------------------------
# Which classes hypr-max-on-open is allowed to maximize when a window opens.
# Read from two files, local first so a machine-specific rule always beats a
# shipped default:
#
#   ~/.config/hypr/window-policy.local.conf   (git-ignored, yours)
#   ~/.config/hypr/window-policy.conf         (tracked defaults)
#
# Line format is `<keyword> <regex>`. Three keywords answer "may this class be
# maximized" — always | leave | never — and two more say how many of an app's
# windows count as main windows: `multi` (all of them) and `popup` (a title
# that never does). See window-policy.conf for what each one means and why
# "not listed" means leave the window alone.
HYPR_POLICY_LOCAL=${XDG_CONFIG_HOME:-$HOME/.config}/hypr/window-policy.local.conf
HYPR_POLICY_BASE=${XDG_CONFIG_HOME:-$HOME/.config}/hypr/window-policy.conf

# Find the first policy line whose keyword is one of $1 (an alternation, e.g.
# `always|leave|never`) and whose regex matches $2. Prints
# `<keyword>\t<regex>\t<file>` and returns 0; returns 1 if nothing matched.
#
# First match wins, local file first, so a machine-specific rule always beats a
# shipped default — and within one file the earlier line beats the later one,
# which is what lets `never ^Tor Browser$` sit above the browser families.
# Scanning all the keywords in ONE pass is what keeps that ordering meaningful:
# a per-keyword search would silently prefer whichever keyword was searched for
# first, whatever order the file is written in.
hypr_policy_lookup() {
    local want=$1 subject=$2 file line kw re
    for file in "$HYPR_POLICY_LOCAL" "$HYPR_POLICY_BASE"; do
        [[ -r $file ]] || continue
        while IFS= read -r line || [[ -n $line ]]; do
            # Drop a trailing ` # comment` (a leading-# line then fails the
            # match below and is skipped), then split off the first word.
            # Splitting on whitespace with `read` would break `^Tor Browser$`.
            line=${line%%[[:space:]]#*}
            [[ $line =~ ^[[:space:]]*([a-z]+)[[:space:]]+(.*[^[:space:]])[[:space:]]*$ ]] || continue
            kw=${BASH_REMATCH[1]}
            re=${BASH_REMATCH[2]}
            [[ $kw =~ ^($want)$ ]] || continue
            [[ $subject =~ $re ]] || continue
            printf '%s\t%s\t%s\n' "$kw" "$re" "$file"
            return 0
        done < "$file"
    done
    return 1
}

# Print the verdict for a class: always | leave | never. Unlisted -> leave.
# With any second argument, print `<verdict>\t<regex>\t<file>` instead, so
# `hypr-window-policy show` can say WHICH line decided.
hypr_policy_for() {
    local class=$1 verbose=${2:-} hit
    hit=$(hypr_policy_lookup 'always|leave|never' "$class") \
        || hit=$'leave\t(unlisted)\t(default)'
    if [[ -n $verbose ]]; then
        printf '%s\n' "$hit"
    else
        printf '%s\n' "${hit%%$'\t'*}"
    fi
}

# Does this class have several REAL main windows — a browser, not an app whose
# second window is a dialog? `multi` classes are exempt from hypr-max-on-open's
# one-window-at-a-time rule; see window-policy.conf.
hypr_class_is_multi() {
    hypr_policy_lookup multi "$1" >/dev/null
}

# Is this window title one that is never a main window? Only consulted for
# `multi` classes, as the exception list to their exemption: a browser's
# Picture-in-Picture and Library windows share the class of the real browsing
# windows and must not be sized or remembered like one. Every other class is
# covered by the one-window rule and never asks.
hypr_title_is_popup() {
    [[ -n $1 ]] && hypr_policy_lookup popup "$1" >/dev/null
}

# Turn a literal class into an anchored regex for a policy line, escaping the
# characters that are common in app-ids (`.` in org.gnome.Software, `+` in
# things like gtk+3-demo) and would otherwise match too much.
hypr_policy_regex() {
    local esc
    esc=$(printf '%s' "$1" | sed 's/[][\.^$*+?(){}|\\\/]/\\&/g')
    printf '^%s$\n' "$esc"
}

# Compute a monitor's usable work area. With no arg it uses the focused
# monitor; pass a numeric monitor id to target a specific one.
#
# PREFER hypr_work_area_for (below) when you have a window address. The
# focused *monitor* is not the window's: it follows keyboard focus (see
# misc:mouse_move_focuses_monitor in hyprland.conf), and the caller is usually
# acting on some specific window — which may be neither the focused one nor on
# the focused screen. Sizing a window against the wrong monitor is how windows
# on a second output ended up wearing the laptop's work-area dimensions.
#
# Sets globals:
#   WORK_W, WORK_H  work-area size in logical px (monitor / scale, minus the
#                   reserved zones, e.g. the eww bar)
#   WORK_X, WORK_Y  work-area origin in Hyprland's GLOBAL logical coordinate
#                   space — the monitor's own position plus its reserved
#                   left/top zones.
#   WORK_MON        the monitor's connector name (eDP-1, DP-2, …), so callers
#                   can key per-screen state off the same monitor they just
#                   measured — see hypr-max-on-open's saved geometry.
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
    WORK_MON=$mon_name
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

# Does a window of size $1 x $2 fill the work area last measured by
# hypr_work_area / hypr_work_area_for?
#
# This is the whole definition of "maximized" here: there is no maximize STATE
# to read back — mod+m just applies a geometry (hypr_set_max), deliberately, so
# that a maximized window is still an ordinary floating window. Its SIZE is the
# only thing that says it is maximized, and which screen's work area it is
# wearing is the only thing that says where.
#
# The few px of slack absorb fractional-scale rounding: on the 1.5667-scaled
# laptop panel Hyprland reports a window a pixel or two off the size it was
# handed.
hypr_fills_work_area() {
    local dw=$(( $1 - WORK_W )) dh=$(( $2 - WORK_H ))
    (( ${dw#-} <= 3 && ${dh#-} <= 3 ))
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

# ---------------------------------------------------------------------------
# Snapping
# ---------------------------------------------------------------------------
# A snap is half the work area on one axis (or on both, for a corner), inset by
# a border on every side so the 2px active border of the `snap` chrome renders
# inside the screen instead of half off it. Like maximize, it is a GEOMETRY and
# not a state: nothing records that a window is snapped, so the rectangle has to
# be computable from the work area alone — which is what lets hypr-max-on-open
# recognise one after the fact (hypr_snap_axes) and redo it on another screen.
HYPR_SNAP_BORDER=3

# hypr_snap_geom HORIZ VERT — the rectangle a snap occupies on the work area
# last measured by hypr_work_area. HORIZ is left|right|"" and VERT is
# top|bottom|"", where "" means the whole of that axis:
#
#   (left, "")      left half        ("", top)      top half
#   (right, top)    top-right quarter
#
# Sets SNAP_W/SNAP_H/SNAP_X/SNAP_Y; x/y are GLOBAL coordinates, already offset
# by the work area's origin.
hypr_snap_geom() {
    local horiz=$1 vert=$2 bw=$HYPR_SNAP_BORDER
    local half_w=$(( WORK_W / 2 )) half_h=$(( WORK_H / 2 ))
    case $horiz in
        left)  SNAP_X=$(( WORK_X + bw ))          SNAP_W=$(( half_w - bw - bw )) ;;
        right) SNAP_X=$(( WORK_X + half_w + bw )) SNAP_W=$(( half_w - bw - bw )) ;;
        *)     SNAP_X=$(( WORK_X + bw ))          SNAP_W=$(( WORK_W - bw - bw )) ;;
    esac
    case $vert in
        top)    SNAP_Y=$(( WORK_Y + bw ))          SNAP_H=$(( half_h - bw - bw )) ;;
        bottom) SNAP_Y=$(( WORK_Y + half_h + bw )) SNAP_H=$(( half_h - bw - bw )) ;;
        *)      SNAP_Y=$(( WORK_Y + bw ))          SNAP_H=$(( WORK_H - bw - bw )) ;;
    esac
}

# hypr_snap_axes W H — is a window of this size snapped to the work area last
# measured by hypr_work_area? Sets SNAP_AXIS_X and SNAP_AXIS_Y to `half` or
# `full` and returns 0; returns 1 if the size is not a snap of this screen.
#
# The SIZE says which KIND of snap it is — half on one axis and full on the
# other is an edge half, half on both is a corner quarter — but never which
# SIDE: a left and a right half are the same rectangle in different places.
# Callers that need the side get it from the position.
#
# Full on both axes is the work area inset by a border, which nothing produces:
# maximize fills it exactly (hypr_fills_work_area), so that combination would
# only be a coincidence and is rejected. Same 3px slack as hypr_fills_work_area,
# for the same fractional-scale rounding.
hypr_snap_axes() {
    local bw=$HYPR_SNAP_BORDER d
    d=$(( $1 - (WORK_W / 2 - bw - bw) )); SNAP_AXIS_X=half
    if (( ${d#-} > 3 )); then
        d=$(( $1 - (WORK_W - bw - bw) )); SNAP_AXIS_X=full
        (( ${d#-} > 3 )) && return 1
    fi
    d=$(( $2 - (WORK_H / 2 - bw - bw) )); SNAP_AXIS_Y=half
    if (( ${d#-} > 3 )); then
        d=$(( $2 - (WORK_H - bw - bw) )); SNAP_AXIS_Y=full
        (( ${d#-} > 3 )) && return 1
    fi
    [[ $SNAP_AXIS_X == full && $SNAP_AXIS_Y == full ]] && return 1
    return 0
}

# Snap a window to a half or quarter of ITS OWN monitor's work area, with the
# borderless-but-bordered "snap" chrome. hypr-snap-window is one caller (the
# mod+Ctrl+h/j/k/l binds); hypr-max-on-open is the other, redoing a snap on the
# screen a window was moved to. Both go through here so that "snapped left" means
# exactly the same pixels however it was asked for.
hypr_set_snap() {
    local addr=$1 horiz=$2 vert=$3
    hypr_work_area_for "$addr" || return 1
    hypr_snap_geom "$horiz" "$vert"
    hyprctl --batch \
        "dispatch resizewindowpixel exact ${SNAP_W} ${SNAP_H},address:${addr}; \
         dispatch movewindowpixel exact ${SNAP_X} ${SNAP_Y},address:${addr}; \
         $(hypr_chrome "$addr" snap)" >/dev/null
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
    hypr_fills_work_area "$w" "$h" && mode=max
    hyprctl --batch \
        "dispatch resizewindowpixel exact ${w} ${h},address:${addr}; \
         dispatch movewindowpixel exact ${x} ${y},address:${addr}; \
         $(hypr_chrome "$addr" "$mode")" >/dev/null
}

# ---------------------------------------------------------------------------
# Remembered geometry
# ---------------------------------------------------------------------------
# A window's size and position is remembered per class, KWin-style, under
# ~/.cache/hypr-window-state/<class>.json. hypr-max-on-open restores it when a
# window opens and writes it when one is resized or closed; hypr-window-policy
# prints it (`show`), deletes it (`forget`) and writes it on demand
# (`remember`, bound to mod+Alt+Shift+m). It lives here because both of them
# need to agree on the path and the schema.
#
# Saved-geometry schema version:
#
#   v1  x/y as GLOBAL coordinates. Only ever worked on a single monitor at 0x0:
#       a window closed on a second output saved an x beyond the laptop's
#       width and, once undocked, came back off-screen where it couldn't be
#       reached.
#   v2  x/y RELATIVE to the work area of the monitor the window was on, so a
#       position means the same thing on any output. The SIZE was still one
#       number for the whole class, which two screens of different sizes
#       cannot share: a browser closed maximized on the laptop reopened
#       1440x930 on the 1920-wide Dell, and maximizing it there made every
#       later laptop window 1920 wide (clamped back to 1440, which then
#       overwrote the Dell's size again on the next close — a permanent
#       ping-pong where neither screen ended up right).
#   v3  one entry PER MONITOR, keyed by connector name, plus the work area it
#       was measured against:
#         {v:3, last:"eDP-1", mons:{"eDP-1":{width,height,x,y,aw,ah}, …}}
#       A window opening on a screen it has been on before gets that screen's
#       own geometry. On a screen it has never been on, the most recently
#       saved entry is REINTERPRETED for this one via reanchor_axis (in
#       hypr-max-on-open) — aw/ah is what makes that possible, because it
#       turns "1440 px wide" back into "as wide as the screen".
#
# v1 is discarded by the reader (fall back to the policy). v2 is still read — as
# a single monitor-less entry, restored exactly as it was before, so an existing
# cache keeps working — and upgraded to v3 the next time the window is saved.
HYPR_STATE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/hypr-window-state
HYPR_GEOM_VERSION=3

# Path to a class's remembered-geometry file. The class is sanitised for use as
# a filename: almost never needed in practice, defensive against a class with a
# slash in it.
hypr_geom_file() {
    printf '%s/%s.json\n' "$HYPR_STATE_DIR" "$(printf '%s' "$1" | tr '/' '_')"
}

# Remember a geometry for a class: hypr_save_geometry CLASS W H X Y [MON_ID].
#
# x/y arrive as GLOBAL coordinates (straight off `hyprctl clients`.at) and are
# stored relative to the work-area origin of MON_ID (default: the focused
# monitor) — see the schema note above.
#
# Writes only THAT monitor's entry and leaves the other screens' alone, so
# maximizing a browser on the Dell can't shrink it on the laptop. The work area
# it was measured in is stored alongside, which is what lets the entry be
# re-read for a screen it has never been on.
hypr_save_geometry() {
    local class=$1 w=$2 h=$3 x=$4 y=$5 mon_id=${6:-}
    local saved
    saved=$(hypr_geom_file "$class")

    if [[ $mon_id =~ ^[0-9]+$ ]]; then
        hypr_work_area "$mon_id" || return 1
    else
        hypr_work_area || return 1
    fi

    # Carry over the other monitors' entries. Anything older than v3 is
    # dropped rather than migrated: there is no record of which screen it came
    # from, and guessing "this one" would put the laptop's size under the
    # Dell's name. It has already been restored from by then anyway.
    local prev
    prev=$(jq -c 'if (.v? // 0) == 3 then (.mons // {}) else {} end' "$saved" 2>/dev/null) \
        || prev='{}'
    [[ -z $prev || $prev == null ]] && prev='{}'

    mkdir -p "$HYPR_STATE_DIR"
    jq -n --argjson v "$HYPR_GEOM_VERSION" --arg mon "$WORK_MON" \
          --argjson prev "$prev" \
          --argjson w "$w" --argjson h "$h" \
          --argjson x "$(( x - WORK_X ))" --argjson y "$(( y - WORK_Y ))" \
          --argjson aw "$WORK_W" --argjson ah "$WORK_H" \
        '{v: $v, last: $mon,
          mons: ($prev + {($mon): {width: $w, height: $h, x: $x, y: $y,
                                   aw: $aw, ah: $ah}})}' \
        > "$saved.tmp" && mv "$saved.tmp" "$saved"
}
