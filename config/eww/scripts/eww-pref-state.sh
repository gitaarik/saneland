#!/usr/bin/env bash
#
# Seed an eww UI-preference variable from disk, then block.
#
# UI preferences (e.g. "show the volume percentage next to the systray
# audio icon") are not live system state, so there's nothing to poll: we
# emit the persisted value once at startup/reload and then sleep. Live
# changes come from eww-pref-toggle.sh, which writes the state file AND
# pushes the new value with `eww update`. Keeping the deflisten alive
# (rather than exiting) stops eww from treating the source as dead.
#
# Usage: eww-pref-state.sh <name> [default]
#   <name>    preference key — also the eww var name and state filename
#   [default] value emitted when no state file exists (default: true)

set -uo pipefail

name=${1:?usage: eww-pref-state.sh <name> [default]}
default=${2:-true}

state_file="${XDG_STATE_HOME:-$HOME/.local/state}/eww/$name"

value=$default
[[ -r $state_file ]] && value=$(<"$state_file")
# Normalise anything unexpected back to the default.
[[ $value == true || $value == false ]] || value=$default

echo "$value"

exec sleep infinity
