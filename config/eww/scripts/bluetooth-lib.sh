#!/usr/bin/env bash
#
# Shared helpers for the eww bluetooth scripts. Sourced (not executed).
#
# The point of this file is one idea: BlueZ's `Connected: yes` is not the
# same as "usably connected". BlueZ can hold a phantom link — the device
# powered off out of range and the supervision timeout hasn't fired yet,
# or a login-time auto-reconnect brought the ACL link up but the audio
# profile never came together. In both cases `bluetoothctl devices
# Connected` still lists the device, so the widget used to show it as
# connected when there was no working audio route (the "disconnect then
# reconnect to fix it" symptom).
#
# For AUDIO devices we cross-check PipeWire: a truly usable connection has
# a live `bluez_output`/`bluez_input` node, not just a card. No node ->
# treat as not connected. This is only *partially* independent of BlueZ
# (PipeWire's module-bluez5 subscribes to the same D-Bus), so it reliably
# catches the profile-never-came-up case but NOT the pure supervision-
# timeout phantom. It's a real improvement, not a complete fix.
#
# NON-audio devices (mice, keyboards, controllers) have no PipeWire node
# by nature, so they are exempt and keep trusting BlueZ verbatim.
#
# Graceful degrade: if pactl/PipeWire isn't reachable we set
# BT_PW_AVAILABLE=0 and callers fall back to trusting BlueZ, so a dead
# PipeWire never produces false "disconnected" rows.

bt_audio_class_dir="${XDG_RUNTIME_DIR:-/tmp}/bluetooth-audio-class"

# bt_is_audio MAC -> prints "audio" or "other".
# A device's class is static, so the answer is cached per-MAC under
# $XDG_RUNTIME_DIR (cleared on reboot, re-derived lazily). The one
# `bluetoothctl info` call only happens the first time a given MAC is
# seen — deliberately avoiding a per-emit info call, which the state
# script's design goes out of its way to skip for performance.
bt_is_audio() {
    # NB: separate `local` statements — in `local a=$1 b=$a`, bash expands
    # every RHS before any assignment, so `b` would see the OLD (empty)
    # `a`. Splitting makes `cache` actually see the mac.
    local mac=$1
    local cache="$bt_audio_class_dir/$mac"
    local info verdict
    if [[ -f $cache ]]; then
        cat "$cache"
        return
    fi
    mkdir -p "$bt_audio_class_dir"
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    if grep -qiE '^[[:space:]]*(Icon: audio|UUID: (Audio Sink|Audio Source|Advanced Audio|Headset|Handsfree))' <<<"$info"; then
        verdict=audio
    else
        verdict=other
    fi
    printf '%s' "$verdict" > "$cache"
    printf '%s' "$verdict"
}

# bt_pipewire_macs populates two GLOBALS (it can't just print, because
# callers need the availability flag too and command substitution runs in
# a subshell that can't set the parent's variables):
#   BT_PW_AVAILABLE = 1 if pactl ran, else 0 (fall back to trusting BlueZ)
#   BT_PW_MACS      = newline-separated colon/upper MACs with a live node
# Node names look like `bluez_output.10_94_97_61_F5_2D.1`.
bt_pipewire_macs() {
    BT_PW_AVAILABLE=0
    BT_PW_MACS=""
    command -v pactl >/dev/null 2>&1 || return
    local nodes
    nodes=$( { pactl list short sinks; pactl list short sources; } 2>/dev/null ) || return
    BT_PW_AVAILABLE=1
    BT_PW_MACS=$(grep -oE 'bluez_(output|input)\.[0-9A-Fa-f_]+' <<<"$nodes" \
        | sed -E 's/^bluez_(output|input)\.//' \
        | tr 'a-f_' 'A-F:' \
        | sort -u)
}
