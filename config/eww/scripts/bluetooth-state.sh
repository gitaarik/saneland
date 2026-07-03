#!/usr/bin/env bash
#
# Stream bluetooth adapter state + paired devices for eww's deflisten.
# Emits one JSON object per change:
#   {"powered": bool, "transitioning": bool,
#    "connected_count": int, "devices": [{mac, name, connected}]}
#
# Reactivity:
#   - `gdbus monitor --system --dest org.bluez` for D-Bus PropertyChanged
#     signals (snappy: covers Powered, Connected, new/removed pairings).
#   - Adaptive poller: 300ms while a pending-target file is in flight
#     (so the "Turning on/off..." indicator clears promptly after the
#     transition completes), 5s otherwise. Replaces a recursive emit
#     scheduler that snowballed when bluetoothctl calls were slow.
#
# Per-emit cost is dominated by bluetoothctl invocations, so we make
# exactly THREE: one `show` for adapter state, one `devices Paired`
# for the list, one `devices Connected` for the connected subset.
# Doing per-device `bluetoothctl info MAC` would 8x that cost and was
# the source of an earlier perf cliff.

set -uo pipefail

source "${BASH_SOURCE[0]%/*}/bluetooth-lib.sh"

pending_file="${XDG_RUNTIME_DIR:-/tmp}/bluetooth-pending-target"
device_state_dir="${XDG_RUNTIME_DIR:-/tmp}/bluetooth-device-state"
lockfile="${XDG_RUNTIME_DIR:-/tmp}/eww-bluetooth-state.lock"
pid_file="${XDG_RUNTIME_DIR:-/tmp}/eww-bluetooth-state.pid"
mkdir -p "$device_state_dir"

emit() {
    local powered powered_bool power_state transitioning target
    local paired_raw connected_raw connected_mac_set
    local devices_json connected_count lines=()

    paired_raw=$(bluetoothctl devices Paired 2>/dev/null)
    connected_raw=$(bluetoothctl devices Connected 2>/dev/null)
    powered=$(bluetoothctl show 2>/dev/null \
        | awk -F': ' '/^[[:space:]]+Powered/{print $2; exit}')
    [[ $powered == yes ]] || powered=no

    # Build a lookup set of connected MACs (newline-separated, easy
    # to grep against).
    connected_mac_set=$(echo "$connected_raw" \
        | awk '/^Device /{print $2}')

    # Phantom-connection guard (see bluetooth-lib.sh): for audio devices
    # we additionally require a live PipeWire node, so a stale BlueZ
    # `Connected: yes` with no usable audio route reads as disconnected.
    # Only fetch the PipeWire node set when something is actually
    # connected — nothing connected means nothing to second-guess, and we
    # skip the pactl calls entirely on the idle 5s poll.
    BT_PW_AVAILABLE=0
    BT_PW_MACS=""
    [[ -n $connected_mac_set ]] && bt_pipewire_macs

    # IFS=' ' is explicit because the SIGUSR1 trap (which calls this
    # function) can fire mid-`IFS= read -r line` in the outer gdbus
    # loop, leaving IFS empty — without restoring it here, `read -r
    # mac name` slurps the whole line into $mac.
    while IFS=' ' read -r mac name; do
        [[ -z $mac ]] && continue
        local connected=false device_state
        if grep -qxF "$mac" <<< "$connected_mac_set"; then
            connected=true
            # Downgrade a phantom audio link: BlueZ says connected but
            # there's no live PipeWire node, so the audio route isn't
            # actually up. Non-audio devices (no node by nature) and the
            # PipeWire-unreachable case both skip this and trust BlueZ.
            if (( BT_PW_AVAILABLE )) && [[ $(bt_is_audio "$mac") == audio ]]; then
                grep -qxF "$mac" <<< "$BT_PW_MACS" || connected=false
            fi
        fi
        # Per-device state file written by bluetooth-device.sh:
        # "connecting" / "disconnecting" / "error". If we've reached
        # the implicit target (connected == true after a connect attempt,
        # connected == false after a disconnect attempt), clear the file
        # — bluez has confirmed and the in-progress indicator should
        # vanish.
        if [[ -f $device_state_dir/$mac ]]; then
            device_state=$(<"$device_state_dir/$mac")
            case "$device_state" in
                connecting)    $connected && { rm -f "$device_state_dir/$mac"; device_state=idle; } ;;
                disconnecting) $connected || { rm -f "$device_state_dir/$mac"; device_state=idle; } ;;
            esac
        else
            device_state=idle
        fi
        lines+=("$(jq -nc --arg m "$mac" --arg n "$name" \
                          --argjson c "$connected" --arg s "$device_state" \
            '{mac: $m, name: $n, connected: $c, state: $s}')")
    done < <(echo "$paired_raw" | sed -E 's/^Device ([^ ]+) (.+)$/\1 \2/')

    if (( ${#lines[@]} > 0 )); then
        devices_json="[$(IFS=,; echo "${lines[*]}")]"
    else
        devices_json='[]'
    fi
    connected_count=$(echo "$devices_json" | jq '[.[] | select(.connected)] | length')
    # Name of the first connected device, for the optional systray label
    # (mirrors the network widget's connected-SSID text). Empty when
    # nothing is connected.
    connected_name=$(echo "$devices_json" | jq -r 'first(.[] | select(.connected) | .name) // ""')

    # `transitioning` covers the "user clicked the toggle, adapter is
    # on its way" window. Primary source: the pending-target file
    # dropped by bluetooth-toggle.sh BEFORE invoking bluetoothctl.
    #   - Min 500ms hold so the UI gets a visible beat even when
    #     bluez completes near-instantly.
    #   - Cleared when actual `powered` matches target.
    #   - Stale guard at 10s wipes the file if target never reached.
    # Secondary source: bluez's PowerState=off-enabling/on-disabling
    # for transitions triggered externally (blueman, rfkill CLI, etc.).
    transitioning=false
    target=""
    if [[ -f $pending_file ]]; then
        local pending target_reached age_ms mtime_ns now_ns
        pending=$(<"$pending_file")
        target=$pending
        target_reached=false
        if [[ ($pending == on && $powered == yes) || ($pending == off && $powered == no) ]]; then
            target_reached=true
        fi
        # date -r gives nanoseconds; bash handles 19-digit ints fine.
        # (stat -c '%N' is the *quoted filename*, not nanoseconds.)
        mtime_ns=$(date -r "$pending_file" +%s%N 2>/dev/null)
        now_ns=$(date +%s%N)
        age_ms=$(( (now_ns - ${mtime_ns:-0}) / 1000000 ))

        if (( age_ms < 500 )); then
            transitioning=true
        elif $target_reached || (( age_ms > 10000 )); then
            rm -f "$pending_file"
            target=""
        else
            transitioning=true
        fi
    fi
    if ! $transitioning; then
        power_state=$(bluetoothctl show 2>/dev/null \
            | awk -F': ' '/^[[:space:]]+PowerState/{print $2; exit}')
        case "$power_state" in
            off-enabling) transitioning=true; target=on  ;;
            on-disabling) transitioning=true; target=off ;;
        esac
    fi

    [[ $powered == yes ]] && powered_bool=true || powered_bool=false
    jq -nc \
        --argjson powered "$powered_bool" \
        --argjson trans "$transitioning" \
        --arg     target "$target" \
        --argjson cc "$connected_count" \
        --arg     cn "$connected_name" \
        --argjson devs "$devices_json" \
        '{powered: $powered, transitioning: $trans, target: $target,
          connected_count: $cc, connected_name: $cn, devices: $devs}'
}

# Blocking flock — events that arrive while an emit is running queue
# behind it instead of being dropped (matters when bluez fires several
# PropertyChanged signals in rapid succession during a power-on cycle).
emit_locked() {
    {
        flock 9
        emit
    } 9>"$lockfile"
}

# Expose our PID so bluetooth-toggle.sh and bluetooth-device.sh can
# SIGUSR1 us for an immediate re-emit (no waiting for the next poll
# tick — the click handler writes state, signals, the UI updates).
#
# The trap sets a flag instead of calling emit_locked directly. Calling
# emit_locked from the trap deadlocks: if the poller (or any other emit)
# already holds `flock`, the trap's nested emit_locked opens a fresh FD
# 9 and blocks on the same lock, but the trap can't return — leaving
# the main shell wedged. The flag is drained at the top of each gdbus
# read iteration (the read returns on signal, so we get a wakeup
# immediately even when no actual line arrived).
echo $$ > "$pid_file"
need_emit=false
trap 'need_emit=true' USR1

emit_locked

# Adaptive poller: 300ms cadence while a power transition is pending
# OR a per-device connect/disconnect attempt is in flight, 5s otherwise.
# Fast cadence guarantees we re-emit shortly after the 500ms power-toggle
# hold expires and after bluez confirms device state changes, even if
# no further PropertyChanged signals arrive.
(
    while :; do
        if [[ -f $pending_file ]] \
           || [[ -n $(find "$device_state_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]; then
            sleep 0.3
        else
            sleep 5
        fi
        emit_locked
    done
) &
poller_pid=$!
trap 'kill $poller_pid 2>/dev/null; rm -f "$pid_file"' EXIT INT TERM

# Real-time updates from bluez D-Bus signals. PropertiesChanged covers
# Powered / Connected / Paired flips; we re-emit on any of them.
#
# Using process substitution (not `|`) so the `while` runs in the main
# shell — keeps the SIGUSR1 trap installed where signals are delivered
# (bash resets traps in pipeline subshells).
#
# Wrapped in `while :; do ... done` so a transient dbus hiccup (e.g.
# bluez restarting, or this script starting before the system bus is
# fully up post-login) doesn't kill us — without the outer loop, gdbus
# exiting drops the read loop to EOF and the whole script exits,
# leaving eww staring at the deflisten's :initial JSON forever.
while :; do
    # Open gdbus monitor on FD 3 so `read -u 3 -t` can poll it. A bare
    # `while read; do ... done < <(...)` would block read indefinitely
    # (bash's `read` doesn't wake on signal interrupt — the trap fires
    # but the read stays blocked), so the SIGUSR1 flag would never get
    # drained without a periodic timeout.
    exec 3< <(gdbus monitor --system --dest org.bluez 2>/dev/null)
    while :; do
        # 0.3s timeout doubles as the SIGUSR1-drain cadence. If we got
        # a line, dispatch it; if we got a timeout, just fall through
        # to the flag check below.
        if IFS= read -u 3 -t 0.3 -r line; then
            case "$line" in
                *PropertiesChanged*) emit_locked ;;
            esac
        elif (( $? <= 128 )); then
            # Non-timeout failure = EOF on the gdbus pipe; break to the
            # outer respawn loop.
            break
        fi
        if $need_emit; then
            need_emit=false
            emit_locked
        fi
    done
    exec 3<&-
    sleep 2
done
