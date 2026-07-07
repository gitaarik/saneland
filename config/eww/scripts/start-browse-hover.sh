#!/usr/bin/env bash
#
# Debounce the start menu's "Browse apps" hover. Arming waits a short grace
# period before revealing the apps fly-out (start-apps-open=true), so a
# pointer that merely passes over the row on its way elsewhere (e.g. down to
# the power buttons, or over to "Search apps") doesn't flash the pop-out
# open. Cancelling kills a still-pending timer when the pointer leaves the
# row before the grace elapses.
#
# Usage:
#   start-browse-hover.sh arm      # eventbox onhover:     start the open timer
#   start-browse-hover.sh cancel   # eventbox onhoverlost: drop a pending timer
#
# A click (the button's onclick) still opens instantly — it bypasses this
# script, so a deliberate tap has no delay.
#
# Cancel-on-leave also guards the Browse -> Search hand-off: "Search apps"
# sets start-apps-open=false onhover, so a still-counting arm timer would
# otherwise fire true a moment later and re-flash the pop-out. Leaving the
# Browse row fires onhoverlost first, which kills that pending timer.

set -uo pipefail

delay=0.2
pid_file=${XDG_RUNTIME_DIR:-/tmp}/eww-start-browse-hover.pid

# Whatever the action, first drop any timer still counting down from a
# previous hover — a fresh arm restarts the clock, a cancel just clears it.
if [[ -f $pid_file ]]; then
  kill "$(<"$pid_file")" 2>/dev/null || true
  rm -f "$pid_file"
fi

case ${1:?missing action: arm|cancel} in
  arm)
    { sleep "$delay"; eww update start-apps-open=true; rm -f "$pid_file"; } &
    echo $! > "$pid_file"
    disown
    ;;
  cancel)
    : # the kill above already dropped any pending timer
    ;;
  *)
    echo "start-browse-hover.sh: unknown action '$1'" >&2
    exit 1
    ;;
esac
