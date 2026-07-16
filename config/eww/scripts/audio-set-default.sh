#!/usr/bin/env bash
# Route audio to a device the popup offered. The popup stays open so the
# user can see the new active row (●) and pick a different one without
# reopening; they close it by clicking outside.
#
# Usage: audio-set-default.sh sink|source NAME
#        audio-set-default.sh profile PROFILE CARD
#
# `profile` exists because a card's HDMI output has no sink until that card's
# profile selects it — see audio-devices.sh for why the picker mixes the two.

set -euo pipefail

kind=${1:?missing kind (sink|source|profile)}
name=${2:?missing device name}

sink_names() { pactl -f json list sinks 2>/dev/null | jq -r '.[].name' | sort; }

case "$kind" in
  sink)   pactl set-default-sink   "$name" ;;
  source) pactl set-default-source "$name" ;;
  profile)
    card=${3:?missing card name}

    # Switching the profile creates the sink but does NOT make it default —
    # WirePlumber leaves the existing default alone (verified: with a Bluetooth
    # speaker as default, selecting HDMI added the sink and audio kept playing
    # out of Bluetooth). Without this the row would look like it did nothing.
    #
    # The new sink is found by diffing the sink list around the switch rather
    # than by guessing its name from the card's: sink naming is a PipeWire
    # implementation detail, the diff is not.
    before=$(sink_names)
    pactl set-card-profile "$card" "$name"

    # The sink appears asynchronously — poll rather than sleep a fixed guess.
    for _ in $(seq 1 20); do
      sleep 0.1
      new=$(comm -13 <(printf '%s\n' "$before") <(sink_names) | head -1)
      if [[ -n $new ]]; then
        pactl set-default-sink "$new"
        break
      fi
    done
    ;;
  *) echo "Usage: $0 sink|source NAME | profile PROFILE CARD" >&2; exit 1 ;;
esac
