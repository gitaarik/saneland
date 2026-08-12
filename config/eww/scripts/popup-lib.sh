#!/usr/bin/env bash
#
# Shared helpers for the popup scripts. Sourced, not executed — sourcing keeps
# the click path to a single process, which matters because the dismiss routes
# are now bound permanently and so run on EVERY left click and Escape.
#
# shellcheck shell=bash

runtime=${XDG_RUNTIME_DIR:-/tmp}

# "A popup may be open."
#
# Deliberately an OVER-approximation, and the direction matters. It is written
# before a popup is opened and removed only after eww has been observed with none
# left, so it can be wrong by saying "maybe" when the answer is no — which costs
# one wasted check that then clears it — but it cannot say "no" while a popup is
# on screen. A false "no" would make a popup undismissable; a false "maybe" is
# self-correcting. Nothing reads it as truth: it is a fast path in front of eww,
# which remains the authority.
popup_marker=$runtime/eww-popup-any-open

# Cheap enough to sit in front of every click: ~1ms, against ~14ms to ask eww and
# ~73ms for the full cursor-and-layers check.
popups_possible() { [[ -e $popup_marker ]]; }

mark_popups_possible() { : > "$popup_marker"; }

# The popups eww currently has open — the authoritative answer.
# start-apps-popup is excluded throughout: it is the start menu's companion,
# opened and closed with start-popup, never in its own right.
open_popups() {
  eww active-windows 2>/dev/null | cut -d: -f1 \
    | grep -- '-popup$' | grep -vx 'start-apps-popup'
}

# Drop the marker once eww reports nothing open, then look again: a popup opened
# in that gap must not be left behind a marker that says "none". Re-checking is
# the whole safety of the fast path, and it is one cheap query.
clear_marker_if_empty() {
  [[ -n $(open_popups) ]] && return 0
  rm -f "$popup_marker"
  [[ -n $(open_popups) ]] && mark_popups_possible
  return 0
}

# How long a popup is protected from a --settled dismiss. One click on a tray
# icon is delivered twice — Hyprland fires the click-outside route while eww
# fires the icon's onclick and opens a new popup — so without this a click could
# close the very popup it was opening. Measured without the guard: with the
# dismiss landing ~200ms in, 4 of 16 switches closed what they had just opened.
# This is now the only timing rule left in the popup system.
SETTLE_MS=400

# Age of a popup in milliseconds, or a large number if it was never stamped.
# Unstamped counts as old, so a missing stamp can never make one undismissable.
popup_age_ms() {
  local stamp=$runtime/eww-popup-opened-$1
  [[ -r $stamp ]] || { echo 999999; return; }
  echo $(( ( $(date +%s%N) - $(<"$stamp") ) / 1000000 ))
}

stamp_popup()   { date +%s%N > "$runtime/eww-popup-opened-$1"; }
unstamp_popup() { rm -f "$runtime/eww-popup-opened-$1"; }

# Append a line to the popup log. Called only AFTER the fast path, so an idle
# click never pays for it. The log is how the next misbehaviour gets diagnosed
# from evidence instead of inference — see docs or `tail -f $popup_log`.
popup_log=$runtime/eww-popup.log
popup_log() {
  printf '%s %-26s %s\n' "$(date +%T.%3N)" "${0##*/}" "$*" >> "$popup_log" 2>/dev/null
}

# Keep the log from growing without bound over a long session. Called from the
# open path only — never from the click path.
trim_popup_log() {
  local lines
  lines=$(wc -l < "$popup_log" 2>/dev/null) || return 0
  (( lines > 2000 )) || return 0
  tail -n 500 "$popup_log" > "$popup_log.tmp" 2>/dev/null && mv "$popup_log.tmp" "$popup_log"
}
