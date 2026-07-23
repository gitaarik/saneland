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
# hypr-state.sh's per-monitor keys.

set -uo pipefail

# The daemon is (auto-)started by the first `eww open` below and inherits this
# env. GtkCalendar reads first-day-of-week from LC_TIME; en_GB gives a
# Monday-first week with English names (see the autostart note in
# hyprland.conf). A no-op for later syncs — the daemon is already up by then.
export LC_TIME=en_GB.UTF-8

sync_bars() {
  local n i idx open names
  # Connector names sorted by Hyprland id; index i (the GDK --screen index) is
  # the i-th of these. The COUNT drives coverage; the NAME is passed to the bar.
  mapfile -t names < <(hyprctl monitors -j | jq -r 'sort_by(.id) | .[].name')
  n=${#names[@]}
  [[ $n -gt 0 ]] || return

  open=$(eww active-windows 2>/dev/null | cut -d: -f1)

  # Open a bar on every monitor index that doesn't already have one, telling it
  # which screen it's on via --arg mon=<connector>.
  for (( i = 0; i < n; i++ )); do
    grep -qx "bar-$i" <<<"$open" || eww open bar --id "bar-$i" --screen "$i" --arg "mon=${names[i]}"
  done

  # Close bars with no monitor behind them: the legacy single-instance `bar`
  # (from the old autostart), and any bar-<index> at index >= current count
  # (its monitor was unplugged).
  while IFS= read -r w; do
    case "$w" in
      bar)   eww close "$w" ;;
      bar-*) idx=${w#bar-}; (( idx >= n )) && eww close "$w" ;;
    esac
  done < <(grep -E '^bar(-[0-9]+)?$' <<<"$open")
}

sync_bars

if [[ ${1:-} == --watch ]]; then
  # Re-sync whenever Hyprland reports a monitor change. Same socket2 + ncat
  # pattern as popup-toggle.sh's dismiss listener. The short sleep lets GDK
  # register the new output before we ask eww to target its index.
  sock=${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock
  ncat -U "$sock" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      monitoradded*|monitorremoved*)
        sleep 0.5
        sync_bars
        ;;
    esac
  done
fi
