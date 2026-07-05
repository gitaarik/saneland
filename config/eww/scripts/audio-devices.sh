#!/usr/bin/env bash
# Emits JSON describing audio sinks (outputs) and non-monitor sources (inputs)
# for the eww audio popup. Each device is annotated with `default: true` if
# it is the current PipeWire default sink/source.

set -euo pipefail

default_sink=$(pactl get-default-sink 2>/dev/null || echo "")
default_source=$(pactl get-default-source 2>/dev/null || echo "")

sinks=$(pactl -f json list sinks 2>/dev/null | jq --arg d "$default_sink" '
  [.[] | {
    name: .name,
    description: (.properties["device.description"] // .description),
    default: (.name == $d)
  }]
')

sources=$(pactl -f json list sources 2>/dev/null | jq --arg d "$default_source" '
  [ .[]
    | select(.properties["device.class"] != "monitor")
    | {
        name: .name,
        description: (.properties["device.description"] // .description),
        default: (.name == $d)
      }
  ]
')

# `loaded: true` lets the popup tell a real (possibly empty) result apart from
# the defpoll's initial placeholder, so it can show a loading hint before the
# first poll lands instead of a blank box. This script only ever emits real
# output, so the flag is always true here.
jq -n --argjson sinks "$sinks" --argjson sources "$sources" \
  '{sinks: $sinks, sources: $sources, loaded: true}'
