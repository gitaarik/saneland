#!/usr/bin/env bash
#
# Adjust the default sink's volume by 1% — but only while the audio
# popup is open (gated by the `open-popup` eww var). Bound from the
# audio widget's :onscroll with the scroll-direction marker eww emits
# for `{}` (either `+` or `-`).
#
# The gate lives here rather than in :onscroll's expression because
# eww's `{}` substitution is only reliable when it appears as a literal
# in the top-level onscroll string — burying it inside a conditional's
# string-result is brittle.

set -uo pipefail

[[ $(eww get open-popup 2>/dev/null) == "audio-popup" ]] || exit 0

# eww's :onscroll substitutes `{}` with `up`/`down`. wpctl set-volume
# wants `+`/`-` instead — translate.
case ${1:?missing scroll direction} in
  up)   sign=+ ;;
  down) sign=- ;;
  *)    echo "audio-scroll: unknown direction '$1'" >&2; exit 1 ;;
esac

wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "1%${sign}"
