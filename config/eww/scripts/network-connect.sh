#!/usr/bin/env bash
#
# Connect to / disconnect from a wifi network. Decision flow:
#   - already active for this SSID  -> `nmcli connection down` (disconnect)
#   - saved profile for this SSID   -> `nmcli connection up` (use stored creds)
#   - new, open                     -> `nmcli device wifi connect`
#   - new, secured (WPA/WPA2)       -> rofi prompts for password, then connect
#   - new, enterprise (802.1X/EAP)  -> delegate to nm-connection-editor (notify)
#
# Per-SSID transient state file under $XDG_RUNTIME_DIR/network-wifi-state/
# (hashed SSID), read by network-state.sh on each emit and surfaced as
# device.state in the JSON. Same convention as bluetooth-device.sh.
#
# Stale connecting/disconnecting markers on OTHER networks are wiped on
# each click so a click on B drops B's spinner once A's attempt is
# abandoned (mirrors the bluetooth click flow). Error markers persist
# until the next click or a popup re-open.

set -uo pipefail

ssid=${1:?missing SSID}

state_dir="${XDG_RUNTIME_DIR:-/tmp}/network-wifi-state"
state_pid_file="${XDG_RUNTIME_DIR:-/tmp}/eww-network-state.pid"
mkdir -p "$state_dir"

ssid_hash() { printf '%s' "$1" | sha1sum | cut -c1-16; }
my_hash=$(ssid_hash "$ssid")

# Clear stale state files on other networks.
for f in "$state_dir"/*; do
    [[ -f $f ]] || continue
    [[ $(basename "$f") == "$my_hash" ]] && continue
    rm -f "$f"
done

# Look up SSID's current state.
active=false
in_use=$(nmcli -t -f IN-USE,SSID device wifi list 2>/dev/null \
    | awk -F: -v s="$ssid" '$2==s && $1=="*" {print "yes"; exit}')
[[ $in_use == yes ]] && active=true

saved=false
if nmcli -t -f NAME,TYPE connection show 2>/dev/null \
    | grep -qxF "${ssid}:802-11-wireless"; then
    saved=true
fi

security=$(nmcli -t -f SSID,SECURITY device wifi list 2>/dev/null \
    | awk -F: -v s="$ssid" '$1==s {print $2; exit}')

# Decide action.
action=""
if $active; then
    action=disconnect
    echo disconnecting > "$state_dir/$my_hash"
elif $saved; then
    action=connect_saved
    echo connecting > "$state_dir/$my_hash"
elif [[ -z $security || $security == "--" ]]; then
    action=connect_open
    echo connecting > "$state_dir/$my_hash"
elif [[ $security == *"802.1X"* || $security == *"EAP"* ]]; then
    notify-send -a "Network" "Enterprise wifi" \
        "Use Network Settings to configure 802.1X / EAP networks." 2>/dev/null
    exit 1
else
    # WPA/WPA2 — prompt password via rofi-dmenu (-password masks input).
    # rofi -dmenu reads candidates from stdin; for a password input we
    # have none, so feed /dev/null and rely on user typing. -password
    # masks the input. rofi exits non-zero on Esc.
    pw=$(rofi -dmenu -password -p "Password for $ssid" 2>/dev/null </dev/null)
    # rofi exits non-zero on Esc; rolling that back means no spinner ever
    # appeared, which is what we want.
    [[ -z $pw ]] && exit 0
    action="connect_new:$pw"
    echo connecting > "$state_dir/$my_hash"
fi

# Kick the state script so the connecting indicator shows up
# immediately (vs waiting up to 300ms for the next poll tick).
[[ -f $state_pid_file ]] && kill -USR1 "$(<"$state_pid_file")" 2>/dev/null

# Run nmcli in the background — connect can take 5-15s. On success the
# active flag flips and network-state.sh's emit clears the marker; on
# failure we leave an "error" marker for the popup.
(
    case "$action" in
        disconnect)
            if nmcli connection down "$ssid" >/dev/null 2>&1; then
                rm -f "$state_dir/$my_hash"
            else
                echo error > "$state_dir/$my_hash"
            fi
            ;;
        connect_saved)
            if nmcli connection up "$ssid" >/dev/null 2>&1; then
                rm -f "$state_dir/$my_hash"
            else
                echo error > "$state_dir/$my_hash"
            fi
            ;;
        connect_open)
            if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
                rm -f "$state_dir/$my_hash"
            else
                echo error > "$state_dir/$my_hash"
            fi
            ;;
        connect_new:*)
            password=${action#connect_new:}
            if nmcli device wifi connect "$ssid" password "$password" >/dev/null 2>&1; then
                rm -f "$state_dir/$my_hash"
            else
                echo error > "$state_dir/$my_hash"
            fi
            ;;
    esac
    [[ -f $state_pid_file ]] && kill -USR1 "$(<"$state_pid_file")" 2>/dev/null
) &
disown
