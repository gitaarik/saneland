#!/usr/bin/env bash
#
# Stream the current default-sink (output) and default-source (input)
# volume + mute state for eww's deflisten. Emits one JSON object per change:
#   {"volume": 50, "muted": false, "in_volume": 80, "in_muted": false}
# `volume`/`muted` are the output; `in_volume`/`in_muted` the input.
#
# Driven by `pactl subscribe`: a re-read fires on any sink/source event or
# on a server event (which covers default-sink/source swaps from the popup).

set -uo pipefail

emit() {
  local sink_out src_out volume muted in_volume in_muted
  sink_out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return
  volume=$(awk '{print int($2*100)}' <<< "$sink_out")
  if grep -q MUTED <<< "$sink_out"; then muted=true; else muted=false; fi

  # The source can be absent (no mic); fall back to a muted-zero state so the
  # input slider still renders rather than the whole emit failing.
  src_out=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
  if [ -n "$src_out" ]; then
    in_volume=$(awk '{print int($2*100)}' <<< "$src_out")
    if grep -q MUTED <<< "$src_out"; then in_muted=true; else in_muted=false; fi
  else
    in_volume=0
    in_muted=false
  fi

  jq -nc --argjson v "$volume" --argjson m "$muted" \
         --argjson iv "$in_volume" --argjson im "$in_muted" \
    '{volume: $v, muted: $m, in_volume: $iv, in_muted: $im}'
}

# Start `pactl subscribe` BEFORE the initial emit so events fired during
# eww startup (notably wireplumber restoring the saved sink volume) are
# buffered in the pipe instead of lost in the gap between emit and
# subscribe — without this the widget shows whatever transient value
# wpctl read (often 0% or 100%) until the user nudges the volume.
# The `until` loop covers the other half: wpctl itself can fail briefly
# while wireplumber is still coming up under graphical-session.target.
pactl subscribe 2>/dev/null | {
  until emit; do sleep 0.2; done
  while IFS= read -r line; do
    case "$line" in
      *"on sink"*|*"on source"*|*"on server"*) emit ;;
    esac
  done
}
