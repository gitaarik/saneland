#!/usr/bin/env bash
#
# install.sh — symlink this repo's configs and scripts into place.
#
#   config/<app>  ->  ~/.config/<app>      (whole-dir symlink)
#   bin/<script>  ->  ~/.local/bin/<script> (per-file symlink)
#
# Existing real files/dirs are backed up to <name>.bak-<timestamp> before
# being replaced. Re-running is safe: already-correct symlinks are left
# alone. Nothing is installed system-wide and no package is touched — see
# the dependency list in README.md and install those with your package
# manager first.
#
# Usage: ./install.sh [--dry-run]

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
DRY=0
[[ ${1:-} == --dry-run ]] && DRY=1

say()  { printf '  %s\n' "$*"; }
head() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# link SRC DEST — back up an existing DEST, then symlink DEST -> SRC.
link() {
  local src=$1 dest=$2
  # Already the intended symlink? Nothing to do.
  if [[ -L $dest && $(readlink -f "$dest") == "$(readlink -f "$src")" ]]; then
    say "ok    $dest"
    return
  fi
  if [[ $DRY == 1 ]]; then
    say "link  $dest -> $src"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  # Back up anything real (or a wrong symlink) that's in the way.
  if [[ -e $dest || -L $dest ]]; then
    mv "$dest" "$dest.bak-$STAMP"
    say "bak   $dest -> $dest.bak-$STAMP"
  fi
  ln -s "$src" "$dest"
  say "link  $dest -> $src"
}

# Default active-theme symlinks (dark). Flip later with `theme light|dark`.
# Format: "<relative symlink path> <target>"
DEFAULT_THEME_LINKS=(
  "config/eww/eww.scss          eww-dark.scss"
  "config/hypr/border-colors.conf border-colors-dark.conf"
  "config/rofi/colorScheme.rasi colorSchemes/dark.rasi"
  "config/rofi/guiSize.rasi     guiSizes/normal.rasi"
  "config/swaync/style.css      style-dark.css"
  "config/gtk-3.0/settings.ini  settings-dark.ini"
  "config/gtk-3.0/gtk.css       gtk-dark.css"
)

head "Active-theme symlinks (default: dark)"
for entry in "${DEFAULT_THEME_LINKS[@]}"; do
  read -r rel target <<<"$entry"
  full="$REPO/$rel"
  if [[ -L $full || -e $full ]]; then
    say "ok    $rel"
  elif [[ $DRY == 1 ]]; then
    say "link  $rel -> $target"
  else
    ln -s "$target" "$full"
    say "link  $rel -> $target"
  fi
done

head "Local overrides (created from *.example, never clobbered)"
# Files where your machine-specific settings live. Git-ignored; seeded once
# from the committed example, then yours to edit. Re-running install never
# overwrites an existing one.
LOCAL_FILES=(
  "config/hypr/local.conf  config/hypr/local.conf.example"
  "config/eww/local.yuck   config/eww/local.yuck.example"
)
for entry in "${LOCAL_FILES[@]}"; do
  read -r dest src <<<"$entry"
  if [[ -e $REPO/$dest ]]; then
    say "ok    $dest"
  elif [[ $DRY == 1 ]]; then
    say "seed  $dest (from $(basename "$src"))"
  else
    cp "$REPO/$src" "$REPO/$dest"
    say "seed  $dest (from $(basename "$src"))"
  fi
done

head "Config → ~/.config  (files in local/<app> override the base per-file)"
# Each config/<app> is whole-dir symlinked into ~/.config — simple, and it
# auto-picks-up new upstream files. BUT if you keep a local/<app> overlay
# (git-ignored — your private tweaks), that app is instead materialised as a
# real directory of per-file symlinks: each file comes from local/<app> if
# present there, else from config/<app>. So you can override or add individual
# files (e.g. local/eww/eww.yuck) without forking the whole app. See
# docs/CUSTOMIZING.md.
for base in "$REPO"/config/*; do
  [[ -e $base || -L $base ]] || continue
  app=$(basename "$base")
  over="$REPO/local/$app"
  dest="$HOME/.config/$app"

  if [[ ! -d $over ]]; then
    link "$base" "$dest"                     # no overlay → plain whole-dir symlink
    continue
  fi

  say "overlay $app  (local/$app over base)"
  # Switching to per-file mode: a prior whole-dir symlink must go, or mkdir
  # would write through it into the repo.
  if [[ -L $dest ]]; then
    [[ $DRY == 1 ]] || mv "$dest" "$dest.bak-$STAMP"
    say "bak   $dest -> $dest.bak-$STAMP"
  fi
  [[ $DRY == 1 ]] || mkdir -p "$dest"
  # Union of relative paths from base + overlay; overlay wins per file.
  while IFS= read -r rel; do
    [[ -z $rel ]] && continue
    if [[ -e $over/$rel || -L $over/$rel ]]; then
      link "$over/$rel" "$dest/$rel"
    else
      link "$base/$rel" "$dest/$rel"
    fi
  done < <(
    { [[ -d $base ]] && ( cd "$base" && find . \( -type f -o -type l \) -printf '%P\n' )
      ( cd "$over" && find . \( -type f -o -type l \) -printf '%P\n' ); } | sort -u
  )
done

head "Scripts → ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for f in "$REPO"/bin/*; do
  link "$f" "$HOME/.local/bin/$(basename "$f")"
done

cat <<'NOTE'

Done. Next steps:

  1. Install the runtime dependencies for your distro:
       ./deps.sh              # or ./deps.sh --print to just see the list
  2. Add yourself to the `input` group for the Alt-Tab MRU daemon:
       sudo usermod -aG input "$USER"   # then re-login
  3. Set your monitors / app choices in ~/.config/hypr/local.conf
     (seeded above from local.conf.example — the base config stays generic).
  4. Drop wallpapers into wallpapers/dark/ and wallpapers/light/.
  5. Enable the hyprbars plugin (see README.md → hyprbars).
  6. Log into the "Hyprland (uwsm-managed)" session, or reload:
       hyprctl reload && eww reload
  7. Switch theme any time with:  theme dark   |   theme light

Keybinds and window rules in config/hypr/hyprland.conf are opinionated
defaults — adapt to taste.
NOTE
