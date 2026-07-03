#!/usr/bin/env bash
#
# Emit Hyprland state as JSON-per-line for eww's deflisten.
#
# Shape:
#   {
#     "focused_workspace": 1,
#     "tag_focused": [true,false,...,false],     // 12 elements, 1-indexed -> [0..11]
#     "windows": [
#       {"id": "0x...", "title": "...", "app_id": "...", "workspace": 1,
#        "focused": true, "on_focused_tag": true}
#     ]
#   }
#
# Windows are emitted in the order recorded in ~/.cache/hypr-window-order
# (which the hypr-window-order daemon maintains as append-on-open).

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
    echo '{"focused_workspace":0,"tag_focused":[false,false,false,false,false,false,false,false,false,false,false,false],"windows":[]}'
    exit 0
fi

emit() {
    local fws active clients order

    fws=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // 0')
    active=$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // ""')
    clients=$(hyprctl -j clients 2>/dev/null) || clients='[]'

    # Order from the state file (workspace_id<TAB>addr per line).
    if [[ -r $state_file ]]; then
        order=$(awk -F'\t' '{ printf "%s\n%s\n", $1, $2 }' "$state_file" | jq -Rsc '
            split("\n") | map(select(length > 0))
            | [range(0; length / 2)] as $i
            | $i | map({workspace: (. * 2 | tonumber? // 0), addr_idx: (. * 2 + 1)})
        ' 2>/dev/null || order='[]')
    else
        order='[]'
    fi

    # Simpler: just read tab-separated lines into a JSON array.
    local order_json
    order_json=$(awk -F'\t' 'BEGIN{print "["} NR>1{print ","} {printf "{\"ws\":%s,\"addr\":\"%s\"}", $1, $2} END{print "]"}' "$state_file" 2>/dev/null)
    [[ -z $order_json ]] && order_json='[]'

    jq -nc \
       --argjson clients "$clients" \
       --argjson order "$order_json" \
       --argjson fws "$fws" \
       --argjson icon_map "$icon_map_json" \
       --arg active "$active" '
        ($clients | map({(.address): .}) | add // {}) as $by_addr
        | ($clients | map(.workspace.id) | unique) as $populated
        | {
            focused_workspace: $fws,
            tag_focused: ([range(1; 13)] | map(. == $fws)),
            tag_visible: ([range(1; 13)] | map(. == $fws or (. as $n | $populated | any(. == $n)))),
            windows: ($order | map(
                . as $row
                | ($by_addr[.addr] // null) as $c
                | if $c == null then empty
                  else {
                    id: $c.address,
                    title: $c.title,
                    app_id: $c.class,
                    icon: ($icon_map[$c.class]
                           // $icon_map[$c.class | ascii_downcase]
                           // $c.class),
                    workspace: $c.workspace.id,
                    focused: ($c.address == $active),
                    on_focused_tag: ($c.workspace.id == $fws)
                  } end
            ))
          }
    ' 2>/dev/null
}

# Initial emit
emit

# Listen for events that change the state
ncat -U "$sock" | while IFS= read -r line; do
    case "$line" in
        openwindow*|closewindow*|movewindow*|activewindow*|workspace*|renameworkspace*|windowtitle*) emit ;;
    esac
done
