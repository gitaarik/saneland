#!/usr/bin/env bash
#
# Stream NetworkManager state for eww's deflisten. Emits JSON:
#   {
#     "kind": "wifi"|"ethernet"|"none",
#     "wifi_enabled": bool,
#     "wifi_transitioning": bool,
#     "wifi_target": "on"|"off"|"",
#     "ethernet_connected": bool,
#     "connected_ssid": "",
#     "networks": [
#       {ssid, signal, secured, saved, active, state}
#     ]
#   }
#
# Same reactivity pattern as bluetooth-state.sh: gdbus monitor on the
# system bus for org.freedesktop.NetworkManager PropertyChanged signals,
# plus an adaptive poller (300ms while a wifi toggle or per-network
# connect attempt is in flight, 5s idle). SIGUSR1 from the click
# handlers sets a flag drained by `read -t` so the popup updates within
# a tick instead of waiting for the next poll.

set -uo pipefail

pending_wifi_file="${XDG_RUNTIME_DIR:-/tmp}/network-wifi-pending"
wifi_state_dir="${XDG_RUNTIME_DIR:-/tmp}/network-wifi-state"
popup_open_file="${XDG_RUNTIME_DIR:-/tmp}/eww-network-popup-open"
lockfile="${XDG_RUNTIME_DIR:-/tmp}/eww-network-state.lock"
pid_file="${XDG_RUNTIME_DIR:-/tmp}/eww-network-state.pid"
mkdir -p "$wifi_state_dir"

# SSIDs can contain any byte (including `/`); hash for safe filenames.
ssid_hash() { printf '%s' "$1" | sha1sum | cut -c1-16; }

emit() {
    local wifi_enabled wifi_enabled_bool wifi_transitioning wifi_target
    local kind=none connected_ssid="" ethernet_connected=false
    local networks_json='[]' lines=() networks_loaded=false

    # Wifi radio
    wifi_enabled=$(nmcli -t -f WIFI radio 2>/dev/null)
    [[ $wifi_enabled == enabled ]] && wifi_enabled_bool=true || wifi_enabled_bool=false

    # Active connections — find current SSID and ethernet status.
    while IFS=':' read -r name type _; do
        case $type in
            802-11-wireless) connected_ssid=$name; [[ $kind == none ]] && kind=wifi ;;
            802-3-ethernet)  ethernet_connected=true; kind=ethernet ;;
        esac
    done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)

    # Wifi transitioning: pending file from network-toggle-wifi.sh with
    # the same 500ms hold / 10s stale-guard pattern as bluetooth.
    wifi_transitioning=false
    wifi_target=""
    if [[ -f $pending_wifi_file ]]; then
        local pending target_reached age_ms mtime_ns now_ns
        pending=$(<"$pending_wifi_file")
        wifi_target=$pending
        target_reached=false
        if [[ ($pending == on && $wifi_enabled == enabled) \
           || ($pending == off && $wifi_enabled != enabled) ]]; then
            target_reached=true
        fi
        mtime_ns=$(date -r "$pending_wifi_file" +%s%N 2>/dev/null)
        now_ns=$(date +%s%N)
        age_ms=$(( (now_ns - ${mtime_ns:-0}) / 1000000 ))
        # Min 1500ms hold — wifi radio flips much faster than a
        # bluetooth adapter spinning up, and with the ~300ms emit lag
        # (gdbus read timeout) a shorter hold leaves only a few
        # hundred ms of visible indicator. 1.5s gives a comfortable
        # "I clicked and something is happening" beat. Stale guard at
        # 10s wipes the file if the target is never reached (rfkill
        # block, modem yanked).
        if (( age_ms < 1500 )); then
            wifi_transitioning=true
        elif $target_reached || (( age_ms > 10000 )); then
            rm -f "$pending_wifi_file"
            wifi_target=""
        else
            wifi_transitioning=true
        fi
    fi

    # Network list: only when wifi is enabled AND the popup is open.
    # `nmcli device wifi list` forces NM to surface fresh scan data
    # (driving NetworkManager's CPU) and is by far the heaviest query
    # in this emit — there's no point paying for it when the user
    # isn't looking. The popup-open flag is touched by popup-toggle.sh
    # (for network-popup) and removed by popup-dismiss.sh. nmcli wifi
    # list output has one entry per BSSID — we dedupe by SSID, keeping
    # the strongest-signal seen. Sort by signal desc, then connected first.
    if [[ $wifi_enabled == enabled && -f $popup_open_file ]]; then
        # We're actually building the list this emit, so the popup can
        # drop its "Searching…" placeholder. While the popup is closed
        # this stays false, which means the first emit after a (re)open —
        # the one the popup waits on — arrives with networks_loaded still
        # false in eww's held state, keeping the loading row up until the
        # list lands rather than flashing an empty pane.
        networks_loaded=true
        # Map of SSID -> last-activation unix timestamp, used both to
        # mark a network as "saved" and to sort the saved group most-
        # recently-used first. NM stores this in connection.timestamp;
        # we read it terse so the parse is split-on-`:`.
        declare -A saved_ts
        while IFS=':' read -r name ts type; do
            [[ $type == "802-11-wireless" ]] || continue
            saved_ts[$name]=${ts:-0}
        done < <(nmcli -t -f NAME,TIMESTAMP,TYPE connection show 2>/dev/null)

        declare -A best_signal best_security best_inuse
        while IFS=':' read -r ssid signal security in_use; do
            [[ -z $ssid ]] && continue
            if [[ -z ${best_signal[$ssid]:-} || $signal -gt ${best_signal[$ssid]} ]]; then
                best_signal[$ssid]=$signal
                best_security[$ssid]=$security
                best_inuse[$ssid]=$in_use
            fi
        done < <(nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE device wifi list 2>/dev/null)

        for ssid in "${!best_signal[@]}"; do
            local signal=${best_signal[$ssid]}
            local security=${best_security[$ssid]}
            local in_use=${best_inuse[$ssid]}
            local secured=true
            [[ -z $security || $security == "--" ]] && secured=false
            local saved=false ts=0
            if [[ -n "${saved_ts[$ssid]:-}" ]]; then
                saved=true
                ts=${saved_ts[$ssid]}
            fi
            # `active` is whether THIS ssid (any BSSID) is the one we're
            # connected to. Using IN-USE from the deduped entry would
            # miss the active AP when a stronger same-SSID AP exists.
            local active=false
            [[ $ssid == "$connected_ssid" ]] && active=true

            # Per-SSID state file mirrors bluetooth-device-state, with
            # one tweak: a 1000ms minimum hold before clearing on
            # success. `nmcli connection up` for a saved-with-strong-
            # signal network can complete in under 300ms — without the
            # hold the spinner never visibly renders between click and
            # the row's settle-to-active state. Errors persist (clear
            # only on click-another or popup re-open).
            local hash=$(ssid_hash "$ssid")
            local state_file=$wifi_state_dir/$hash
            local net_state=idle
            if [[ -f $state_file ]]; then
                net_state=$(<"$state_file")
                local nstate_age_ms nstate_mtime_ns nstate_now_ns
                nstate_mtime_ns=$(date -r "$state_file" +%s%N 2>/dev/null)
                nstate_now_ns=$(date +%s%N)
                nstate_age_ms=$(( (nstate_now_ns - ${nstate_mtime_ns:-0}) / 1000000 ))
                case $net_state in
                    connecting)
                        if $active && (( nstate_age_ms >= 1000 )); then
                            rm -f "$state_file"; net_state=idle
                        fi ;;
                    disconnecting)
                        if ! $active && (( nstate_age_ms >= 1000 )); then
                            rm -f "$state_file"; net_state=idle
                        fi ;;
                esac
            fi

            lines+=("$(jq -nc \
                --arg s "$ssid" \
                --argjson sig "$signal" \
                --argjson sec "$secured" \
                --argjson sv "$saved" \
                --argjson ac "$active" \
                --argjson tsj "$ts" \
                --arg st "$net_state" \
                '{ssid:$s, signal:$sig, secured:$sec, saved:$sv, active:$ac,
                  timestamp:$tsj, state:$st}')")
        done
        # Sort key tuple: active first (group 0), then saved-but-not-
        # active by most-recently-used (group 1, sorted -timestamp),
        # then unsaved by strongest signal (group 2, ties broken by
        # -signal which also kicks in within saved for same-timestamp
        # entries).
        if (( ${#lines[@]} > 0 )); then
            networks_json=$(printf '%s\n' "${lines[@]}" \
                | jq -sc 'sort_by(
                    (if .active then 0 elif .saved then 1 else 2 end),
                    -.timestamp,
                    -.signal
                  )')
        fi
    fi

    jq -nc \
        --arg kind "$kind" \
        --argjson we "$wifi_enabled_bool" \
        --argjson wt "$wifi_transitioning" \
        --arg wtg "$wifi_target" \
        --argjson ec "$ethernet_connected" \
        --arg cs "$connected_ssid" \
        --argjson nets "$networks_json" \
        --argjson nl "$networks_loaded" \
        '{kind:$kind, wifi_enabled:$we, wifi_transitioning:$wt, wifi_target:$wtg,
          ethernet_connected:$ec, connected_ssid:$cs, networks:$nets,
          networks_loaded:$nl}'
}

# Blocking flock — same rationale as bluetooth-state.sh (events that
# arrive while emit is mid-run queue behind it rather than getting
# dropped).
emit_locked() {
    {
        flock 9
        emit
    } 9>"$lockfile"
}

# Expose PID for SIGUSR1 from click handlers. Trap just sets a flag —
# calling emit_locked from the trap deadlocks if the poller is mid-emit
# (the trap's nested flock blocks but the trap can't return). The flag
# gets drained by the `read -t` timeout in the main loop.
echo $$ > "$pid_file"
need_emit=false
trap 'need_emit=true' USR1

emit_locked

# Adaptive poller: fast cadence while wifi toggle or per-network
# connect attempts are in flight, 5s idle.
(
    while :; do
        if [[ -f $pending_wifi_file ]] \
           || [[ -n $(find "$wifi_state_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]; then
            sleep 0.3
        else
            sleep 5
        fi
        emit_locked
    done
) &
poller_pid=$!
trap 'kill $poller_pid 2>/dev/null; rm -f "$pid_file"' EXIT INT TERM

# NetworkManager fires PropertiesChanged on the device/connection
# interfaces when wifi connects, scans complete, etc. Wrap gdbus in an
# outer retry loop so a transient dbus race after login doesn't kill
# us (same fix as bluetooth-state.sh).
#
# Debounce/throttle: a single wifi scan produces dozens of events
# (signal-strength PropertiesChanged on every AP, AccessPointAdded
# per network found). Emitting on each one previously had NM busy
# answering nmcli all the time. We throttle to at most one emit per
# `min_emit_interval_ms` from dbus events; the first event in a quiet
# window still fires immediately (no first-event lag).
min_emit_interval_ms=1000
pending=false
now_ms() { echo $(($(date +%s%N) / 1000000)); }
last_emit_ms=$(now_ms)
while :; do
    exec 3< <(gdbus monitor --system --dest org.freedesktop.NetworkManager 2>/dev/null)
    while :; do
        if IFS= read -u 3 -t 0.3 -r line; then
            case "$line" in
                *PropertiesChanged*|*StateChanged*|*AccessPointAdded*|*AccessPointRemoved*)
                    pending=true
                    ;;
            esac
        elif (( $? <= 128 )); then
            break
        fi
        # SIGUSR1 from click handlers / popup open: emit immediately,
        # bypassing the throttle so popup-open feels instant.
        if $need_emit; then
            need_emit=false
            pending=false
            emit_locked
            last_emit_ms=$(now_ms)
        fi
        if $pending; then
            now=$(now_ms)
            if (( now - last_emit_ms >= min_emit_interval_ms )); then
                pending=false
                emit_locked
                last_emit_ms=$now
            fi
        fi
    done
    exec 3<&-
    sleep 2
done
