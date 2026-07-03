#!/usr/bin/env bash
#
# Toggle (or set) an eww UI-preference variable. Persists the choice to a
# state file under XDG_STATE_HOME and pushes it to the running eww
# instance so the bar updates instantly. The state file is read back at
# startup by eww-pref-state.sh.
#
# Usage: eww-pref-toggle.sh <name> [true|false]
#   <name>        preference key — also the eww var name and state filename
#   [true|false]  set explicitly (used by the checkbox); omit to flip

set -uo pipefail

name=${1:?usage: eww-pref-toggle.sh <name> [true|false]}
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/eww"
state_file="$state_dir/$name"
mkdir -p "$state_dir"

if [[ ${2:-} == true || ${2:-} == false ]]; then
    next=$2
else
    current=true
    [[ -r $state_file ]] && current=$(<"$state_file")
    [[ $current == true ]] && next=false || next=true
fi

printf '%s\n' "$next" > "$state_file"
eww update "$name=$next"
