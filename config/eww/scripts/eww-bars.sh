#!/usr/bin/env bash
#
# Spawn the eww bar on EVERY connected monitor, and keep the set in sync as
# monitors are hot-plugged. Replaces the old single `eww open bar` autostart.
#
# Usage:
#   eww-bars.sh            sync once: open a bar on each monitor, close orphans
#   eww-bars.sh --watch    sync once, then re-sync on every monitor add/remove
#
# WHY open by index, not by Hyprland monitor id: eww's `--screen` wants a GDK
# monitor INDEX, which is always contiguous 0..N-1. A Hyprland monitor `id` is
# NOT contiguous — unplug/replug and ids climb (you can end up with 0 and 3).
# But every physical monitor is some index in 0..N-1, so opening the bar on
# each index 0..N-1 lands exactly one bar on every monitor regardless of how
# GDK orders them vs Hyprland. The monitor COUNT is the only fact we take from
# Hyprland; no fragile id<->index mapping to get wrong. (Popups DO need to hit
# a specific monitor — that mapping lives in popup-toggle.sh.)
#
# Each bar is opened with a distinct `--id bar-<index>` so the instances don't
# collide, and `--arg mon=<connector>` so it renders only ITS screen's tags +
# windows (the `(bar)` widget reads hypr.monitors[mon]). The name for index i is
# the i-th monitor sorted by Hyprland id — matching the GDK --screen order and
# hypr-state.sh's per-monitor keys. An index can come to mean a DIFFERENT
# monitor after a hot-unplug, so which connector each bar was opened with is
# tracked too — see bars_state.

set -uo pipefail

# The daemon is started by ensure_daemon below and inherits this env.
# GtkCalendar reads first-day-of-week from LC_TIME; en_GB gives a Monday-first
# week with English names (see the autostart note in hyprland.conf). A no-op
# for later syncs — the daemon is already up by then.
export LC_TIME=en_GB.UTF-8

# Kill every eww daemon and don't return until they are actually gone.
#
# The waiting is the point. A daemon that is unreachable because it is WEDGED —
# rather than absent — is also a daemon that is not processing signals, so its
# SIGTERM sits pending while a replacement comes up beside it: two daemons, two
# full sets of bars, and the older set unreachable by any `eww close`. Hence
# SIGKILL for anything that won't leave, which no amount of wedging can ignore.
#
# It also orders the socket correctly. eww unlinks the socket path on the way
# out, so a straggler dying AFTER its replacement bound would take the new
# daemon's socket with it, leaving a live daemon that nothing can reach — a
# doubled bar that outlives the thing meant to clean it up.
#
# `pkill -x` matches the process name exactly, so it cannot hit this script (or
# `eww-bars.sh`'s own bash). Short-lived eww clients can be caught in the
# crossfire, but they were failing anyway: we only get here when the daemon
# does not answer.
stop_daemons() {
  local i
  pgrep -x eww &>/dev/null || return 0
  pkill -x eww
  for (( i = 0; i < 30; i++ )); do           # up to 3s to go quietly
    pgrep -x eww &>/dev/null || return 0
    sleep 0.1
  done
  pkill -KILL -x eww
  for (( i = 0; i < 20; i++ )); do           # up to 2s more
    pgrep -x eww &>/dev/null || return 0
    sleep 0.1
  done
}

# How many eww DAEMONS are running.
#
# Counted by whether the process has CHILDREN, not by its command line, because
# a daemon eww auto-starts for a client keeps that CLIENT's command line. The
# rogue daemon behind the doubled bar that prompted this was:
#
#     eww open bar --id bar-1 --screen 1 --arg mon=DP-5
#
# — indistinguishable by name or cmdline from the client that spawned it, so
# `pgrep -xcf 'eww daemon'` counted it as zero and the self-heal below sailed
# past a session with two full sets of bars.
#
# What is NOT ambiguous is what a daemon does: it runs the bar's defpoll and
# deflisten scripts as its own children (13 apiece here), while a client —
# `eww open`, `eww update`, the popups' `eww close` — never spawns anything at
# all. So children means daemon, and the case the cmdline count was protecting
# against is still safe: a popup script mid-click is childless and uncounted.
#
# A daemon that has just started and holds no windows yet also has no children
# and so reads as zero. That is the harmless direction to be wrong in — it owns
# no bars to double.
count_daemons() {
  local p n=0
  for p in $(pgrep -x eww); do
    [[ -n $(pgrep -P "$p") ]] && (( n++ ))
  done
  printf '%s\n' "$n"
}

# Bring up exactly ONE eww daemon, and don't return until it answers.
#
# This has to happen before the open loop, which now refuses to start a daemon
# itself (--no-daemonize) and so opens nothing at all if none is up. It used to
# be the loop that started one, and that is the whole history of this bug: with
# nothing running yet, `eww open bar-0` and `eww open bar-1` a moment later BOTH
# forked their own daemon — the first hadn't bound the socket by the time the
# second looked. Each daemon then owned one bar, only the last to bind was
# reachable, and `eww close` could never reach the other. Its bar survived every
# sync forever, and when its monitor was unplugged gtk-layer-shell just moved
# the surface onto a remaining screen: the "two stacked bars after undocking"
# bug (each reserving 30px, so the monitor comes back with reserved=60).
#
# If a daemon is running but unreachable — the state that bug leaves behind, or
# a crash that took the socket with it — stop_daemons clears it first. Its bar
# surfaces are unreachable too, so nothing else will ever clean them up.
#
# A daemon that answers is only trustworthy if it is the ONLY one: a second
# process means a previous restart left a straggler, whose bars answer to
# nobody and so would never be counted or closed below. One config, one daemon
# — and with every `eww open` in the repo carrying --no-daemonize, this function
# is now the only thing in the session that can start one — so treat any surplus
# as the wreckage it is and reset.
#
# See count_daemons for why the surplus check can't just count processes named
# `eww`, or match their command lines.
ensure_daemon() {
  local i
  [[ $(count_daemons) == 1 ]] && eww ping &>/dev/null && return 0
  stop_daemons
  eww daemon &>/dev/null
  for (( i = 0; i < 50; i++ )); do          # up to 5s
    eww ping &>/dev/null && return 0
    sleep 0.1
  done
  echo "eww-bars.sh: eww daemon did not come up" >&2
  return 1
}

# Which connector each open bar was told it is on, index -> name.
#
# `--arg mon=` is fixed when a bar is opened and eww can't be asked about it
# afterwards (`active-windows` gives ids only), so the mapping has to be
# remembered here. It matters because an index does NOT always keep pointing at
# the same screen: indices are a dense 0..N-1 list, so removing a monitor makes
# every later one shift down. Undock the external and index 1 disappears —
# fine, bar-1 is closed. But close the LID while docked and it is index 0 that
# vanishes: the external slides from 1 to 0, bar-1 gets closed as out of range,
# and the bar left on screen is bar-0, still rendering `mon=eDP-1` — the
# workspaces and taskbar of a monitor that isn't there. So a bar whose
# connector no longer matches its index is closed and reopened.
#
# Lives in the runtime dir: bars don't outlive the session and neither should
# this. Anything stale in it is harmless — a bar that isn't actually open is
# opened fresh below, which rewrites its entry.
bars_state=${XDG_RUNTIME_DIR:-/run/user/$UID}/eww-bars.state
declare -A bar_mon=()

load_state() {
  local i m
  bar_mon=()
  [[ -r $bars_state ]] || return 0
  while IFS=$'\t' read -r i m; do
    [[ -n ${i:-} && -n ${m:-} ]] && bar_mon[$i]=$m
  done < "$bars_state"
}

save_state() {
  local i
  for i in "${!bar_mon[@]}"; do printf '%s\t%s\n' "$i" "${bar_mon[$i]}"; done \
    > "$bars_state.tmp" && mv "$bars_state.tmp" "$bars_state"
}

# One sync pass. Returns non-zero if any bar failed to open.
sync_bars_once() {
  local n i idx w open names failed=0
  ensure_daemon || return 1     # a daemon that won't come up is worth a retry
  # Connector names sorted by Hyprland id; index i (the GDK --screen index) is
  # the i-th of these. The COUNT drives coverage; the NAME is passed to the bar.
  mapfile -t names < <(hyprctl monitors -j | jq -r 'sort_by(.id) | .[].name')
  n=${#names[@]}
  # Explicitly SUCCESS: no monitors means nothing to open, and returning the
  # failed test's status instead would tell sync_bars the daemon is wedged and
  # have it kill a perfectly good one — tearing down every bar because hyprctl
  # happened to answer mid-hotplug.
  [[ $n -gt 0 ]] || return 0

  open=$(eww active-windows 2>/dev/null | cut -d: -f1)
  load_state

  # Open a bar on every monitor index that doesn't already have a correct one,
  # telling it which screen it's on via --arg mon=<connector>.
  for (( i = 0; i < n; i++ )); do
    if grep -qx "bar-$i" <<<"$open"; then
      [[ ${bar_mon[$i]:-} == "${names[i]}" ]] && continue   # already right
      eww close "bar-$i"                                    # now a different screen
    fi
    # --no-daemonize: never answer an unreachable daemon by starting a SECOND
    # one. `open` is the only eww subcommand that auto-starts a server (ping,
    # close, update and active-windows all just fail), and that auto-start is
    # what put two daemons on this machine: the daemon wedges for a moment
    # during the hotplug, this very line can't reach it, and eww helpfully
    # forks a rival that binds nothing, answers nothing, and holds a full set
    # of bars no `eww close` can ever reach. A bar that fails to open is
    # recoverable — sync_bars restarts the daemon and opens it — where a rogue
    # daemon is not recoverable at all, so failing here is the better outcome.
    if eww --no-daemonize open bar --id "bar-$i" --screen "$i" \
           --arg "mon=${names[i]}"; then
      bar_mon[$i]=${names[i]}
    else
      failed=1                      # leave bar_mon unset: nothing was opened
    fi
  done

  # Close bars with no monitor behind them: the legacy single-instance `bar`
  # (from the old autostart), and any bar-<index> at index >= current count
  # (its monitor was unplugged).
  while IFS= read -r w; do
    case "$w" in
      bar)   eww close "$w" ;;
      bar-*) idx=${w#bar-}; (( idx >= n )) && { eww close "$w"; unset 'bar_mon[$idx]'; } ;;
    esac
  done < <(grep -E '^bar(-[0-9]+)?$' <<<"$open")

  save_state
  return $failed
}

# Sync the bars, and if the daemon was too wedged to answer an open, restart it
# and sync again.
#
# This is the other half of --no-daemonize. Refusing to spawn a rival daemon
# turns "two stacked bars forever" into "one bar missing", which is only an
# improvement if something then goes and gets the bar — so a failed open is
# taken as proof the daemon is wedged, and stop_daemons removes it (SIGKILL if
# it won't go, since a wedged process isn't handling signals either). The
# retry's ensure_daemon then brings up a fresh one and opens every bar on it.
sync_bars() {
  sync_bars_once && return 0
  echo "eww-bars.sh: a bar did not open; restarting the daemon" >&2
  stop_daemons
  sync_bars_once
}

sync_bars

if [[ ${1:-} == --watch ]]; then
  # Re-sync whenever Hyprland reports a monitor change. Same socket2 + ncat
  # pattern as popup-toggle.sh's dismiss listener. The short sleep lets GDK
  # register the new output before we ask eww to target its index.
  #
  # Read over a fd rather than piping into `while`, so the watcher can actually
  # be stopped — see the "killable event loops" note in docs/ARCHITECTURE.md.
  # Killing the pipeline form left the loop orphaned and still re-syncing bars,
  # which fights a replacement watcher over the same eww windows.
  sock=${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock
  exec 3< <(ncat -U "$sock" 2>/dev/null)
  ncat_pid=$!
  trap 'kill $ncat_pid 2>/dev/null' EXIT
  trap 'exit' INT TERM

  while IFS= read -r line <&3; do
    case "$line" in
      monitoradded*|monitorremoved*)
        sleep 0.5
        sync_bars
        ;;
    esac
  done
fi
