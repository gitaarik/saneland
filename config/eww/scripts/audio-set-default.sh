#!/usr/bin/env bash
# Set the default PipeWire sink or source. The popup stays open so the
# user can see the new active row (●) and pick a different one without
# reopening; they close it by clicking outside.
# Usage: audio-set-default.sh sink|source NAME

set -euo pipefail

kind=${1:?missing kind (sink|source)}
name=${2:?missing device name}

case "$kind" in
  sink)   pactl set-default-sink   "$name" ;;
  source) pactl set-default-source "$name" ;;
  *) echo "Usage: $0 sink|source NAME" >&2; exit 1 ;;
esac
