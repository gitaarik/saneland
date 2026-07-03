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

jq -n --argjson sinks "$sinks" --argjson sources "$sources" \
  '{sinks: $sinks, sources: $sources}'
