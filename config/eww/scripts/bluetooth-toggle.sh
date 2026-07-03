#!/usr/bin/env bash
#
# Toggle the bluetooth adapter power state. On many laptops the adapter
# goes into rfkill-soft-blocked when powered off (PowerState: off-blocked),
# so we unblock via rfkill before asking bluetoothctl to power on —
# otherwise `bluetoothctl power on` silently no-ops.

set -uo pipefail

pending_file="${XDG_RUNTIME_DIR:-/tmp}/bluetooth-pending-target"
state_pid_file="${XDG_RUNTIME_DIR:-/tmp}/eww-bluetooth-state.pid"

powered=$(bluetoothctl show 2>/dev/null \
    | awk -F': ' '/^[[:space:]]+Powered/{print $2; exit}')

if [[ $powered == yes ]]; then
    # Drop the pending-target marker BEFORE issuing the bluetoothctl
    # call. bluetooth-state.sh checks this file to surface a
    # "transitioning" flag until actual state matches the target. The
    # PowerState=off-enabling/on-disabling window from bluez is too
    # brief to catch reliably via post-event polling.
    echo off > "$pending_file"
    bluetoothctl power off >/dev/null
else
    echo on > "$pending_file"
    rfkill unblock bluetooth 2>/dev/null
    bluetoothctl power on >/dev/null
fi

# Kick the state script so the "Turning on/off..." indicator appears
# immediately rather than waiting for the next 300ms poll tick.
[[ -f $state_pid_file ]] && kill -USR1 "$(<"$state_pid_file")" 2>/dev/null
