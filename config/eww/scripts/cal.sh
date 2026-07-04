#!/usr/bin/env bash
#
# Render the clock-popup calendar as JSON for eww, honoring the
# "clock-monday-first" preference (Sunday- vs Monday-first columns).
#
# eww's built-in `calendar` widget wraps GtkCalendar, whose first day of
# the week is fixed by the system locale with no runtime override — so the
# popup renders its own grid from this script instead. The displayed month
# is tracked as an integer offset from the current month in a state file so
# prev/next navigation survives re-render and reload; `today` resets it.
#
# Usage: cal.sh [render|refresh|prev|next|today|scroll <up|down>]
#   render          print the grid JSON on stdout (used by the defpoll)
#   refresh         re-render the current month and push it with `eww update`
#   prev|next       step the month offset, then push
#   today           reset the offset to the current month, then push
#   scroll up|down  step the month via the calendar's :onscroll (up=prev)
set -uo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/eww"
offset_file="$state_dir/clock-cal-offset"
pref_file="$state_dir/clock-monday-first"
mkdir -p "$state_dir"

read_offset() {
    local o=0
    [[ -r $offset_file ]] && o=$(<"$offset_file")
    [[ $o =~ ^-?[0-9]+$ ]] || o=0
    printf '%s' "$o"
}

cmd=${1:-render}
case $cmd in
    render | refresh) ;;
    prev)  printf '%s\n' "$(( $(read_offset) - 1 ))" > "$offset_file" ;;
    next)  printf '%s\n' "$(( $(read_offset) + 1 ))" > "$offset_file" ;;
    today) printf '0\n' > "$offset_file" ;;
    scroll)
        # eww substitutes `{}` with `up`/`down`; scroll up steps back a month.
        case ${2:-} in
            up)   printf '%s\n' "$(( $(read_offset) - 1 ))" > "$offset_file" ;;
            down) printf '%s\n' "$(( $(read_offset) + 1 ))" > "$offset_file" ;;
            *) echo "cal.sh scroll: unknown direction '${2:-}'" >&2; exit 1 ;;
        esac ;;
    *) echo "usage: cal.sh [render|refresh|prev|next|today|scroll <up|down>]" >&2; exit 1 ;;
esac

offset=$(read_offset)
# Default Monday-first when the pref hasn't been set yet — must match the
# clock-monday-first deflisten default in eww.yuck so a pristine install's
# grid and toggle agree. eww-pref-toggle.sh writes this file on first flip.
monday_first=true
[[ -r $pref_file && $(<"$pref_file") == false ]] && monday_first=false

# Displayed month: the 1st of the current month shifted by `offset` months.
first=$(date -d "$(date +%Y-%m-01) $offset month" +%Y-%m-%d)
heading=$(date -d "$first" +'%B %Y')
days_in=$(date -d "$first +1 month -1 day" +%-d)
w=$(date -d "$first" +%w)                       # weekday of the 1st, 0=Sun..6=Sat

# Only the current month carries a "today" highlight.
cur_day=$(date +%-d)
is_current_month=false
[[ $(date -d "$first" +%Y-%m) == $(date +%Y-%m) ]] && is_current_month=true

if [[ $monday_first == true ]]; then
    weekdays=(Mo Tu We Th Fr Sa Su)
    lead=$(( (w + 6) % 7 ))
else
    weekdays=(Su Mo Tu We Th Fr Sa)
    lead=$w
fi

weekdays_json=""
sep=""
for wd in "${weekdays[@]}"; do
    weekdays_json+="$sep\"$wd\""
    sep=","
done

# Pad the trailing week so every row has 7 cells (stable popup height).
total=$(( lead + days_in ))
rows=$(( (total + 6) / 7 ))

weeks_json=""
wksep=""
idx=0
day=1
for (( r = 0; r < rows; r++ )); do
    week=""
    csep=""
    for (( c = 0; c < 7; c++ )); do
        if (( idx < lead || day > days_in )); then
            cell='{"d":"","today":false}'
        else
            today=false
            [[ $is_current_month == true && $day == "$cur_day" ]] && today=true
            cell="{\"d\":$day,\"today\":$today}"
            day=$(( day + 1 ))
        fi
        week+="$csep$cell"
        csep=","
        idx=$(( idx + 1 ))
    done
    weeks_json+="$wksep[$week]"
    wksep=","
done

json="{\"heading\":\"$heading\",\"weekdays\":[$weekdays_json],\"weeks\":[$weeks_json]}"

if [[ $cmd == render ]]; then
    printf '%s\n' "$json"
else
    eww update "cal-data=$json"
fi
