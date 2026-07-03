#!/usr/bin/env bash
#
# Toggle the wifi radio. Drops a pending-target file BEFORE invoking
# nmcli so network-state.sh can surface a "transitioning" indicator
# during the brief flap (same pattern as bluetooth-toggle.sh).

set -uo pipefail

pending_file="${XDG_RUNTIME_DIR:-/tmp}/network-wifi-pending"
state_pid_file="${XDG_RUNTIME_DIR:-/tmp}/eww-network-state.pid"

state=$(nmcli -t -f WIFI radio 2>/dev/null)

# Write the pending-target file FIRST, then signal, THEN call nmcli.
# `nmcli radio wifi on` takes ~1.5s to return — signalling only after
# would push the first emit past the 1000ms minimum hold, so the
# "Turning on..." beat would never appear.
if [[ $state == enabled ]]; then
    echo off > "$pending_file"
else
    echo on > "$pending_file"
fi
[[ -f $state_pid_file ]] && kill -USR1 "$(<"$state_pid_file")" 2>/dev/null

if [[ $state == enabled ]]; then
    nmcli radio wifi off >/dev/null
else
    nmcli radio wifi on >/dev/null
fi
