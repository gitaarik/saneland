#!/usr/bin/env bash
#
# Feed the bar's notification bell: one JSON line per change,
#   {"count": N, "dnd": true|false}
#
# swaync-client's waybar mode (-swb) already pushes a line on every
# notification add/close and DND flip, so this only reshapes it: `text` is the
# count, and `alt` is none / notification / dnd-none / dnd-notification (plus
# inhibited-* variants while something inhibits notifications).
#
# The outer loop is for swaync restarting (`theme` reloads only its CSS, but a
# crash or a `systemctl --user restart swaync` drops the subscription): wait a
# second and subscribe again instead of leaving the bell frozen.

while :; do
    swaync-client -swb 2>/dev/null |
        jq --unbuffered -c '{count: (.text | tonumber? // 0), dnd: (.alt | test("dnd"))}'
    sleep 1
done
