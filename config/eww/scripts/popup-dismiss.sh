#!/usr/bin/env bash
#
# Dismiss an eww popup window: close it, kill its activewindow listener, run its
# close hooks.
#
# Usage:
#   popup-dismiss.sh <window-name>   dismiss that popup
#   popup-dismiss.sh                 dismiss whichever popup is open
#   popup-dismiss.sh --settled       ditto, but leave popups that only just
#                                    opened alone (see SETTLE_MS in popup-lib.sh)
#   popup-dismiss.sh --if-open       ditto, plus the cheap "is anything open at
#                                    all" fast path — the form Escape is bound to
#
# THIS SCRIPT NO LONGER TOUCHES KEYBINDS, and that is the point. The dismiss
# routes are registered once, permanently, in hyprland.conf. Before that, they
# were armed on open and unbound on close, which meant keeping global,
# session-wide compositor state in sync with per-window state from several
# short-lived scripts that a single click starts concurrently — Hyprland fires
# the route while eww fires the widget's onclick, in no defined order. Every bug
# in this system was one shape: two processes disagreeing about the world. Stale
# binds, duplicate binds, a teardown wiping a fresh arm, a ~700ms window where
# nothing was bound at all, and popups left on screen with no way to close them.
# Binding once and never touching it again deletes the entire class: there is no
# shared state left to disagree about. The cost is that the handlers run on every
# click, which is why they start with a ~1ms fast path.
#
# Called from:
#   - popup-toggle.sh's "close" branch (user re-clicks the trigger widget)
#   - app-specific pick scripts (e.g. audio-set-default.sh)
#   - the per-window activewindow listener (focus change to another window)
#   - Hyprland's permanent Escape bind (--if-open) and, via
#     popup-dismiss-if-outside.sh, its permanent mouse:272 bindrn (--settled)
#
# Idempotent: safe to invoke repeatedly, and safe to invoke for a window that is
# already closed.

set -uo pipefail
# shellcheck source=/dev/null
source "$HOME/.config/eww/scripts/popup-lib.sh"

settled_only=0
case ${1:-} in
  --if-open)
    # Escape's fast path. No popup can be open without the marker, so this exits
    # in about a millisecond for every Escape pressed in the rest of the session.
    popups_possible || exit 0
    shift
    ;;
  --settled)
    settled_only=1
    shift
    ;;
esac

dismiss_one() {
  local window=$1 pid_file net_pid_file

  eww close "$window" 2>/dev/null || true
  unstamp_popup "$window"
  # Clear the open-popup gate only if we're the popup that owns it —
  # avoids racing a different popup that just opened (rare but possible
  # if dismiss is called twice in quick succession).
  if [[ $(eww get open-popup 2>/dev/null) == "$window" ]]; then
    eww update open-popup="" 2>/dev/null || true
  fi

  # Per-popup close hooks. Network: drop the popup-open flag so
  # network-state.sh stops building the wifi list.
  case $window in
      network-popup)
          rm -f "$runtime/eww-network-popup-open"
          # Kick the script so it re-emits with networks:[] right away
          # (instead of waiting for the next dbus event / poll tick to
          # notice the flag is gone).
          net_pid_file=$runtime/eww-network-state.pid
          [[ -f $net_pid_file ]] && kill -USR1 "$(<"$net_pid_file")" 2>/dev/null
          ;;
      start-popup)
          # The "Browse apps" pop-out is a companion window of the start menu —
          # close it too and reset its reveal state so it can't linger after
          # the menu is gone.
          eww close start-apps-popup 2>/dev/null || true
          eww update start-apps-open=false 2>/dev/null || true
          ;;
  esac

  pid_file=$runtime/eww-popup-listener-$window.pid
  if [[ -f $pid_file ]]; then
    kill "$(<"$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
  fi
  popup_log "closed $window"
}

if (( $# )); then
  popup_log "dismiss $1"
  dismiss_one "$1"
else
  mapfile -t targets < <(open_popups)
  popup_log "dismiss all${settled_only:+ (settled only)} — open: [${targets[*]:-none}]"
  for w in "${targets[@]}"; do
    [[ -n $w ]] || continue
    if (( settled_only )); then
      age=$(popup_age_ms "$w")
      if (( age < SETTLE_MS )); then
        popup_log "  keep $w — only ${age}ms old, this click probably opened it"
        continue
      fi
    fi
    dismiss_one "$w"
  done
fi

clear_marker_if_empty
