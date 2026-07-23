#!/usr/bin/env bash
#
# Emit Hyprland state as JSON-per-line for eww's deflisten.
#
# Shape — one entry PER MONITOR (keyed by connector name) so each bar shows only
# its OWN screen. Each monitor owns a 12-workspace block: monitors sorted by id,
# rank r -> offset = r*12, so local tags 1..12 map to global workspaces
# off+1..off+12 (laptop 1-12, external 13-24; see hypr-workspace / local.conf).
#
#   {
#     "monitors": {
#       "eDP-1": {
#         "offset": 0,
#         "active": 1,                       // global active ws on this monitor
#         "tag_focused": [true,false,...],   // 12 elems: local tag k -> off+k == active
#         "tag_visible": [true,false,...],   // 12 elems: off+k populated, or == active
#         "windows": [ {"id","title","app_id","icon","focused","on_tag"} ]
#       }, ...
#     }
#   }
#
# Windows are those on the monitor's active workspace, in the creation order
# recorded in ~/.cache/hypr-window-order (append-on-open daemon).

set -uo pipefail

state_file=${XDG_CACHE_HOME:-$HOME/.cache}/hypr-window-order
sock=${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock

# Build a JSON map of (WMClass / filename) -> Icon by scanning .desktop
# files once at script start. Resolves cases like Signal where the
# Hyprland app_id is "signal" but the icon-theme name is "signal-desktop".
# Both raw and lowercase keys are stored so lookup tolerates case drift.
build_icon_map() {
    local out='{'
    local sep=''
    local dir desktop icon wmclass fname

    for dir in /usr/share/applications "$HOME/.local/share/applications" /usr/local/share/applications; do
        [[ -d $dir ]] || continue
        for desktop in "$dir"/*.desktop; do
            [[ -f $desktop ]] || continue
            icon=$(awk -F= '/^Icon=/ { print $2; exit }' "$desktop" | tr -d '\r')
            [[ -z $icon ]] && continue
            wmclass=$(awk -F= '/^StartupWMClass=/ { print $2; exit }' "$desktop" | tr -d '\r')
            fname=$(basename "$desktop" .desktop)

            for key in "$wmclass" "${wmclass,,}" "$fname" "${fname,,}"; do
                [[ -z $key ]] && continue
                # Escape any double-quotes in the icon/key for JSON safety
                k_esc=${key//\"/\\\"}
                i_esc=${icon//\"/\\\"}
                out+="${sep}\"${k_esc}\":\"${i_esc}\""
                sep=','
            done
        done
    done
    out+='}'
    echo "$out"
}

icon_map_json=$(build_icon_map)

if [[ ! -S $sock ]]; then
    echo '{"monitors":{}}'
    exit 0
fi

emit() {
    local active clients monitors order_json

    active=$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // ""')
    clients=$(hyprctl -j clients 2>/dev/null) || clients='[]'
    monitors=$(hyprctl -j monitors 2>/dev/null) || monitors='[]'

    # Window creation order: the hypr-window-order daemon appends
    # "workspace_id<TAB>addr" per line — read it into a JSON array.
    order_json=$(awk -F'\t' 'BEGIN{print "["} NR>1{print ","} {printf "{\"ws\":%s,\"addr\":\"%s\"}", $1, $2} END{print "]"}' "$state_file" 2>/dev/null)
    [[ -z $order_json ]] && order_json='[]'

    # One state object per monitor (keyed by connector name). offset = rank*12,
    # so a monitor's local tags 1..12 are global workspaces off+1..off+12. The
    # bar opened with --arg mon=<name> reads hypr.monitors[mon]. `windows` is
    # pre-filtered to the monitor's active workspace (so every entry is shown).
    jq -nc \
       --argjson clients "$clients" \
       --argjson monitors "$monitors" \
       --argjson order "$order_json" \
       --argjson icon_map "$icon_map_json" \
       --arg active "$active" '
        ($clients | map({(.address): .}) | add // {}) as $by_addr
        | ($clients | map(.workspace.id) | unique) as $populated
        | {
            monitors: (
              ($monitors | sort_by(.id) | to_entries) | map(
                (.key * 12) as $off
                | .value as $m
                | ($m.activeWorkspace.id) as $act
                | {
                    key: $m.name,
                    value: {
                      offset: $off,
                      active: $act,
                      tag_focused: ([range(1; 13)] | map(($off + .) == $act)),
                      tag_visible: ([range(1; 13)] | map(
                          ($off + .) as $g | ($g == $act) or ($populated | any(. == $g)))),
                      windows: ($order | map(
                          ($by_addr[.addr] // null) as $c
                          | if $c == null then empty
                            elif $c.workspace.id != $act then empty
                            else {
                              id: $c.address,
                              title: $c.title,
                              app_id: $c.class,
                              icon: ($icon_map[$c.class]
                                     // $icon_map[$c.class | ascii_downcase]
                                     // $c.class),
                              focused: ($c.address == $active),
                              on_tag: true
                            } end))
                    }
                  }
              ) | from_entries
            )
          }
    ' 2>/dev/null
}

# Initial emit
emit

# Listen for events that change the state
ncat -U "$sock" | while IFS= read -r line; do
    case "$line" in
        openwindow*|closewindow*|movewindow*|activewindow*|workspace*|moveworkspace*|focusedmon*|renameworkspace*|windowtitle*) emit ;;
    esac
done
