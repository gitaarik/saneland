#!/usr/bin/env bash
#
# Toggle a paired bluetooth device's connection by MAC, with feedback
# state for the eww popup (`connecting` while waiting, `error` if
# bluetoothctl returns non-zero).
#
# Usage: bluetooth-device.sh <MAC>
#
# State files at $XDG_RUNTIME_DIR/bluetooth-device-state/<MAC> hold the
# transient state ("connecting", "disconnecting", "error"). bluetooth-
# state.sh reads them on each emit and surfaces device.state in the
# JSON. The file is removed on success (bluez emits Connected change ->
# state script clears the file) or replaced with "error" on failure.
#
# Errors from prior attempts on OTHER devices are wiped on each click —
# the user moving to a different device clears the table. Errors on the
# popup itself are wiped by popup-toggle.sh on re-open.

set -uo pipefail

source "${BASH_SOURCE[0]%/*}/bluetooth-lib.sh"

mac=${1:?missing MAC address}

state_dir="${XDG_RUNTIME_DIR:-/tmp}/bluetooth-device-state"
state_pid_file="${XDG_RUNTIME_DIR:-/tmp}/eww-bluetooth-state.pid"
mkdir -p "$state_dir"

# Clear ANY state on OTHER devices — error markers AND stale
# connecting/disconnecting indicators from a prior click whose
# bluetoothctl hasn't returned yet. The user has moved on; the
# spinner on an abandoned device is noise. Our own state file (if
# any) is overwritten below.
#
# Note: the abandoned bluetoothctl process keeps running in the
# background. When it eventually returns, it'll either rm a file
# that's already gone (harmless) or write a new error file (which
# the user can ignore — it'll clear on the next click or popup
# re-open).
for f in "$state_dir"/*; do
    [[ -f $f ]] || continue
    [[ $(basename "$f") == "$mac" ]] && continue
    rm -f "$f"
done

# Decide direction. Don't blindly call connect — if the device is
# already connected this would be a disconnect attempt.
#
# Three cases, mirroring what the widget shows (see bluetooth-lib.sh):
#   - Usably connected      -> disconnect.
#   - Phantom (BlueZ says connected, but it's an audio device with no
#     live PipeWire node) -> the widget shows it as disconnected, so a
#     click means "make it work": reconnect = disconnect then connect,
#     which is exactly the manual fix the user used to do by hand.
#   - Not connected         -> connect.
reconnect=false
if bluetoothctl info "$mac" 2>/dev/null \
    | grep -q '^[[:space:]]*Connected: yes'; then
    usably_connected=true
    if [[ $(bt_is_audio "$mac") == audio ]]; then
        bt_pipewire_macs
        if (( BT_PW_AVAILABLE )) && ! grep -qxF "$mac" <<< "$BT_PW_MACS"; then
            usably_connected=false
        fi
    fi
    if $usably_connected; then
        action=disconnect
        in_progress=disconnecting
    else
        action=connect
        in_progress=connecting
        reconnect=true
    fi
else
    action=connect
    in_progress=connecting
fi

echo "$in_progress" > "$state_dir/$mac"

# Kick the state script (SIGUSR1) so the popup shows the in-progress
# state without waiting for the next 300ms poll tick.
[[ -f $state_pid_file ]] && kill -USR1 "$(<"$state_pid_file")" 2>/dev/null

# bluetoothctl connect blocks until bluez confirms (5–15s on misses).
# Run in the background so the click handler returns immediately and
# the popup stays responsive.
(
    # Phantom reconnect: drop the stale BlueZ link first so the following
    # connect renegotiates the audio profile from scratch. A short settle
    # lets bluez finish the teardown before we re-link.
    if $reconnect; then
        bluetoothctl disconnect "$mac" >/dev/null 2>&1
        sleep 1
    fi
    if bluetoothctl "$action" "$mac" >/dev/null 2>&1; then
        # On success, bluez fires Connected change; the state script's
        # next emit will see the new value and clear the state file.
        # Remove it eagerly here too so the row settles even if the
        # gdbus event is somehow missed.
        rm -f "$state_dir/$mac"
    else
        echo error > "$state_dir/$mac"
    fi
    [[ -f $state_pid_file ]] && kill -USR1 "$(<"$state_pid_file")" 2>/dev/null
) &
disown
