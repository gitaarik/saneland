#!/usr/bin/env bash
#
# Emit the battery "tier" class suffix for eww's battery widgets:
# critical / warning / low / high, or empty for the normal range.
#
# Single source of truth for the <=10 / <=20 / <=30 / (on-AC & >80) cascade
# that four widget classes share — the systray cell plus the popup icon,
# percent, and charge bar. That cascade used to be written out inline in
# eww.yuck four times; now the thresholds live only here.
#
# Reads the same /sys files as the battery-capacity and ac-online deflistens.
# Polled a little faster than battery-capacity (which is 30s) so plugging in
# reflects in the "high" tier promptly. The popup's percent LABEL still comes
# from battery-info (upower); its tier COLOUR now comes from here. Those two
# percent sources are the same battery, so they agree except (at most) for a
# ~1% window right at a threshold crossing — cosmetic only.

set -uo pipefail

while true; do
    cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    ac=$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1)

    if   [[ -z $cap ]];                     then tier=""
    elif (( cap <= 10 ));                    then tier="critical"
    elif (( cap <= 20 ));                    then tier="warning"
    elif (( cap <= 30 ));                    then tier="low"
    elif [[ $ac == 1 ]] && (( cap > 80 ));   then tier="high"
    else                                          tier=""
    fi

    echo "$tier"
    sleep 5
done
