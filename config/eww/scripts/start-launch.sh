#!/usr/bin/env bash
#
# Dismiss the eww start menu, then "focus-or-launch" an app: if a window
# for it is already open, focus that window (Hyprland switches to its
# workspace); otherwise launch it. Used by the start-popup's pinned-app
# rows (eww.yuck → start-item).
#
# Usage:
#   start-launch.sh <command> [args...]
#       Focus-or-launch by PROCESS (the default). Finds an open window
#       whose PID is a running instance of <command> and focuses it,
#       else launches. No per-app window-class config needed, and it also
#       catches instances started outside this menu (keybind, autostart).
#
#   start-launch.sh --new <command> [args...]
#       Always launch a new instance. For apps that legitimately want
#       many windows regardless of workspace — browsers, terminals.
#
#   start-launch.sh --match <class-regex> <command> [args...]
#       Focus-or-launch by window CLASS instead of process. Escape hatch
#       for the rare app whose process name doesn't match its launch
#       command, so the default pgrep can't find it.
#
# Why process-matching is the default: the command we launch (e.g.
# "thunderbird") usually differs from the window class (e.g.
# "org.mozilla.Thunderbird"), so class-matching would need a hand-kept
# class for every app. But `pgrep -x <command>` gives the PIDs of running
# instances, and Hyprland reports each window's PID — intersect the two
# and we have the window, derived entirely from the command itself. This
# relies on the command's basename matching the process name (true for
# nautilus, thunderbird, …). If it doesn't, nothing matches and we just
# launch — use --match in that case.
#
# `setsid -f` reparents the launched process off the eww daemon (its own
# session + a fork) so the app survives eww restarts (e.g. a theme switch).

set -uo pipefail

"$HOME/.config/eww/scripts/popup-dismiss.sh" start-popup

launch() { exec setsid -f "$@" >/dev/null 2>&1; }

case ${1:-} in
    --new)
        shift
        launch "$@"
        ;;
    --match)
        match=$2
        shift 2
        # Anchor on "^\tclass:" so we don't also match the
        # "initialClass:" line. Detection and focuswindow use the same
        # regex, so they can't disagree.
        if hyprctl clients | grep -qiE "^[[:space:]]*class:[[:space:]]+${match}$"; then
            exec hyprctl dispatch focuswindow "class:${match}"
        fi
        launch "$@"
        ;;
esac

# Default: process-based focus-or-launch.
base=$(basename -- "$1")
pids=$(pgrep -x "$base" || true)
if [[ -n $pids ]]; then
    addr=$(hyprctl clients -j | python3 -c '
import json, sys
pids = {int(x) for x in sys.argv[1].split()}
for c in json.load(sys.stdin):
    if c.get("pid") in pids and c.get("address"):
        print(c["address"]); break
' "$pids")
    if [[ -n $addr ]]; then
        exec hyprctl dispatch focuswindow "address:$addr"
    fi
fi

launch "$@"
