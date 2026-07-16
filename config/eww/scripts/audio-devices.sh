#!/usr/bin/env bash
# Emits JSON describing audio outputs and non-monitor inputs for the eww audio
# popup. Each entry is annotated with `default: true` if it is the current
# PipeWire default sink/source.
#
# `outputs` is NOT just the sink list. A card's HDMI output usually has no sink
# at all until that card's *profile* is switched to it — PipeWire only
# instantiates sinks for the active profile — so an HDMI TV is invisible to a
# sink-only picker even when the cable is carrying audio fine. So outputs =
# live sinks + the card profiles that would create a sink if selected. Each
# entry carries its own `kind` so the row knows which action to take:
#
#   kind "sink"    -> pactl set-default-sink NAME
#   kind "profile" -> pactl set-card-profile CARD NAME   (see audio-set-default.sh)
#
# `inputs` has no such split: sources are always live under the active profile,
# and a profile switch that changes the input is not something the picker needs
# to offer. Hence the asymmetry between the two lists.

set -euo pipefail

default_sink=$(pactl get-default-sink 2>/dev/null || echo "")
default_source=$(pactl get-default-source 2>/dev/null || echo "")

# `.description`, not `.properties["device.description"]`: the latter names the
# DEVICE ("Built-in Audio") and is identical for every profile of a card, so
# the analog and HDMI sinks of one card render as two rows with the same label
# and you can't tell which you're listening to. `.description` is
# profile-qualified ("Built-in Audio Analog Stereo" / "Built-in Audio Digital
# Stereo (HDMI)") and is the same string for devices that have only one output,
# e.g. Bluetooth ("WONDERBOOM 4"), so nothing else reads any longer.
sinks=$(pactl -f json list sinks 2>/dev/null | jq --arg d "$default_sink" '
  [.[] | {
    kind: "sink",
    card: "",
    name: .name,
    description: .description,
    default: (.name == $d)
  }]
')

# Card profiles that would add an output. Filtered hard, because a single HDA
# card advertises ~29 profiles and dumping them all would bury the two or three
# that matter:
#   - available only        — skip outputs with nothing plugged into them
#   - sinks > 0             — skip input-only profiles and "off"
#   - not pro-audio         — raw-device passthrough, not an "output" a user picks
#   - output token differs from the ACTIVE profile's — the active profile's
#     output is already listed above as a real sink; re-listing it as a profile
#     would duplicate the row
# Then one entry per distinct output token, keeping the highest-priority
# variant. Priority already favours the variants that retain an input, so this
# picks e.g. "HDMI + Analog Input" over bare "HDMI" and the mic survives the
# switch.
profiles=$(pactl -f json list cards 2>/dev/null | jq '
  def out_token: if test("output:") then capture("output:(?<o>[^+]+)").o else null end;

  # "Digital Stereo (HDMI) Output + Analog Stereo Input" reads as noise in a
  # narrow popup row: the input half is an implementation detail of which
  # variant was picked below, not something the user chose, and the trailing
  # "Output"/"Duplex" is filler. Stripping both leaves "Digital Stereo (HDMI)"
  # / "Analog Stereo", which — prefixed with the card name — reproduces exactly
  # the label the sink will carry once the profile is active. So a row keeps
  # its identity across the switch instead of renaming itself.
  def profile_label: sub(" Output( \\+ .* Input)?$"; "") | sub(" Duplex$"; "");

  [ .[]
    | .name as $card
    | (.properties["device.description"] // "") as $card_desc
    | (.active_profile | out_token) as $active_out
    | .profiles
    | to_entries
    | map(
        select(.value.available and .value.sinks > 0 and .key != "pro-audio")
        | . + {token: (.key | out_token)}
        | select(.token != null and .token != $active_out)
      )
    | group_by(.token)
    | map(max_by(.value.priority))
    | .[]
    | {
        kind: "profile",
        card: $card,
        name: .key,
        description: (($card_desc + " " + (.value.description | profile_label)) | ltrimstr(" ")),
        default: false
      }
  ]
')

sources=$(pactl -f json list sources 2>/dev/null | jq --arg d "$default_source" '
  [ .[]
    | select(.properties["device.class"] != "monitor")
    | {
        kind: "source",
        card: "",
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
#
# Live sinks sort before profiles: what exists now is what you most likely want
# to pick, and profile rows are the "route somewhere else" escape hatch.
jq -n --argjson sinks "$sinks" --argjson profiles "$profiles" --argjson sources "$sources" \
  '{outputs: ($sinks + $profiles), sources: $sources, loaded: true}'
