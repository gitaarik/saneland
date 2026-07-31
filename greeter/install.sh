#!/usr/bin/env bash
#
# greeter/install.sh — install saneland's login screen (greetd + Hyprland + ReGreet).
#
# This is the ONE part of saneland that touches the system outside your home
# directory, which is why it's opt-in and separate from the top-level
# install.sh. It writes to /etc/greetd, /usr/share/backgrounds and
# /var/lib/greetd, and it needs root.
#
# What it's for: the stock `cage -s -- regreet` greeter spans every connected
# monitor as one surface, so the login box lands on the seam between screens.
# This replaces cage with a stripped-down Hyprland that puts the login window
# on one screen and a wallpaper on the rest. See hyprland.conf for the details.
#
# Usage:
#   sudo ./greeter/install.sh                     install / re-run after a monitor change
#   sudo ./greeter/install.sh --monitor DP-1      pick the login screen explicitly
#   sudo ./greeter/install.sh --wallpaper IMG     pick the background explicitly
#   sudo ./greeter/install.sh --dry-run           show what it would do
#   sudo ./greeter/install.sh --uninstall         put the previous greeter back
#
# Re-run it whenever you change your monitor layout: your `monitor =` lines are
# copied out of ~/.config/hypr/local.conf at install time, not read live (the
# greeter runs as another user and can't see your home).

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO/greeter"
ETC=/etc/greetd
BACKGROUNDS=/usr/share/backgrounds
STAMP=$(date +%Y%m%d-%H%M%S)

MONITOR=""; WALLPAPER=""; DRY=0; UNINSTALL=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --monitor)   MONITOR=${2:?--monitor needs a name}; shift 2 ;;
    --wallpaper) WALLPAPER=${2:?--wallpaper needs a path}; shift 2 ;;
    --dry-run)   DRY=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   sed -n '2,/^set /p' "$0" | sed 's/^# \?//; $d'; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 1 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [[ $DRY == 1 ]]; then say "would: $*"; else "$@"; fi; }

# did MSG — report something that actually happened. Silent under --dry-run,
# where `run` has already printed the "would:" line: a dry run that says
# "write /etc/greetd/hyprland.conf" reads like it wrote it.
did()  { [[ $DRY == 1 ]] || say "$*"; }

# write DEST < stdin — honours --dry-run, since `run` can't take a redirect.
write() {
  local dest=$1
  if [[ $DRY == 1 ]]; then cat >/dev/null; say "would: write $dest"; return; fi
  cat > "$dest"
  say "write $dest"
}

# back_up FILE — move an existing real file aside, once per run.
back_up() {
  [[ -e $1 ]] || return 0
  run cp -a "$1" "$1.bak-$STAMP"
  did "bak   $1 -> $1.bak-$STAMP"
}

[[ $EUID -eq 0 ]] || die "needs root — run it with sudo."

# The user whose monitor layout and wallpapers we copy. Under sudo that's
# SUDO_USER; a bare root shell has no way to know.
TARGET_USER=${SUDO_USER:-}
[[ -n $TARGET_USER && $TARGET_USER != root ]] ||
  die "run this with sudo from your normal user (SUDO_USER is how it finds your config)."
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -d $USER_HOME ]] || die "no home directory for '$TARGET_USER'."

# --- uninstall -------------------------------------------------------------
if [[ $UNINSTALL == 1 ]]; then
  hdr "Restoring the previous greeter"
  [[ -f $ETC/config.toml.saneland-orig ]] ||
    die "no $ETC/config.toml.saneland-orig — nothing to restore from."
  back_up "$ETC/config.toml"
  run cp -a "$ETC/config.toml.saneland-orig" "$ETC/config.toml"
  did "restored $ETC/config.toml"
  say ""
  say "Left in place (harmless — delete if you like): $ETC/hyprland.conf,"
  say "$ETC/machine.conf, $ETC/hyprpaper.conf, $ETC/saneland-greeter*,"
  say "$BACKGROUNDS/saneland-greeter.*"
  say ""
  say "Apply with:  sudo systemctl restart greetd     (ends your session!)"
  exit 0
fi

# --- preconditions ---------------------------------------------------------
hdr "Dependencies"
for bin in greetd regreet Hyprland hyprpaper hyprctl; do
  command -v "$bin" >/dev/null || die "'$bin' not found — install it first."
  say "ok    $bin"
done
[[ -f $ETC/config.toml ]] || die "$ETC/config.toml not found — is greetd installed?"
grep -q '^\[default_session\]' "$ETC/config.toml" ||
  die "$ETC/config.toml has no [default_session] section — patch its command line by hand."

# The account greetd runs the greeter as, read from its own config rather than
# assumed: distros don't all call it `greeter`.
GREETER_USER=$(sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ETC/config.toml" | head -1)
GREETER_USER=${GREETER_USER:-greeter}
id "$GREETER_USER" >/dev/null 2>&1 || die "greeter user '$GREETER_USER' does not exist."
say "ok    greeter user: $GREETER_USER"

# --- which screen gets the login window ------------------------------------
hdr "Monitors"
LOCAL_CONF="$USER_HOME/.config/hypr/local.conf"

MONITOR_LINES=""
if [[ -r $LOCAL_CONF ]]; then
  MONITOR_LINES=$(grep -E '^[[:space:]]*monitor[[:space:]]*=' "$LOCAL_CONF" || true)
fi
if [[ -z $MONITOR_LINES ]]; then
  say "no monitor lines in $LOCAL_CONF — the greeter will auto-detect."
  say "(fine for one screen; add them there if a display needs a specific mode)"
else
  say "copying $(printf '%s\n' "$MONITOR_LINES" | wc -l) monitor line(s) from $LOCAL_CONF"
fi

# monitor_match LINE — the match field of a `monitor =` line (its first
# comma-separated argument), whitespace trimmed.
monitor_match() {
  local m=${1#*=}
  m=${m%%,*}
  m=${m#"${m%%[![:space:]]*}"}
  m=${m%"${m##*[![:space:]]}"}
  printf '%s' "$m"
}

# Preference order for the login screen: --monitor, then the first internal
# panel (eDP-*) named in your monitor lines, then the first connector-named
# line, then a live query of your running session, then the eDP-1 default.
#
# `desc:` matches are skipped on purpose: the windowrule that pins the login
# window wants a connector name, and there's no guarantee a desc: string
# resolves to one at greeter time.
if [[ -z $MONITOR && -n $MONITOR_LINES ]]; then
  while IFS= read -r line; do
    m=$(monitor_match "$line")
    [[ $m == desc:* || -z $m ]] && continue
    [[ $m == eDP-* ]] && { MONITOR=$m; break; }
    [[ -z $MONITOR ]] && MONITOR=$m
  done <<< "$MONITOR_LINES"
fi
if [[ -z $MONITOR ]]; then
  # Ask the running session, if there is one.
  uid=$(id -u "$TARGET_USER")
  MONITOR=$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$uid" \
              hyprctl monitors -j 2>/dev/null |
            sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
fi
MONITOR=${MONITOR:-eDP-1}
say "login screen: $MONITOR"
say "(override with --monitor NAME; the others just show the wallpaper)"

# --- keyboard layout -------------------------------------------------------
# Copied from your session config so the password you type at the greeter is
# the password you think you're typing. local.conf wins over the base config.
hdr "Keyboard"
KB=""
for f in "$USER_HOME/.config/hypr/hyprland.conf" "$LOCAL_CONF"; do
  [[ -r $f ]] || continue
  while IFS= read -r line; do
    line=${line%%#*}                                   # strip inline comment
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -z $line ]] && continue
    key=${line%%=*}; key=${key%"${key##*[![:space:]]}"}
    KB=$(printf '%s\n' "$KB" | grep -v "^    $key = " || true)   # later file wins
    KB="${KB:+$KB$'\n'}    $line"
  done < <(grep -E '^[[:space:]]*kb_(layout|variant|options)[[:space:]]*=' "$f" || true)
done
if [[ -n $KB ]]; then
  printf '%s\n' "$KB" | while IFS= read -r l; do say "copy ${l#    }"; done
else
  say "none found — the greeter will use the X11 default (us)"
fi

# --- wallpaper -------------------------------------------------------------
# Copied to a world-readable path: the greeter user cannot read your home.
# Defaults to the image currently on your desktop (hypr-wallpaper records it),
# else the first of the dark pool.
hdr "Wallpaper"
if [[ -z $WALLPAPER ]]; then
  last=$(cat "$USER_HOME/.cache/wallpaper-last" 2>/dev/null || true)
  if [[ -n $last && -r $last ]]; then
    WALLPAPER=$last
  else
    WALLPAPER=$(find -L "$USER_HOME/.config/hypr/wallpapers/dark" -maxdepth 1 -type f \
                  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
                  2>/dev/null | sort | head -1 || true)
  fi
fi

INSTALLED_WALLPAPER=""
if [[ -n $WALLPAPER && -r $WALLPAPER ]]; then
  ext=${WALLPAPER##*.}
  INSTALLED_WALLPAPER="$BACKGROUNDS/saneland-greeter.${ext,,}"
  run mkdir -p "$BACKGROUNDS"
  # Drop any earlier copy with a different extension — wallpaper.sh globs.
  if [[ $DRY == 0 ]]; then rm -f "$BACKGROUNDS"/saneland-greeter.*; fi
  run install -m 644 "$WALLPAPER" "$INSTALLED_WALLPAPER"
  say "from  $WALLPAPER"
  say "to    $INSTALLED_WALLPAPER"
else
  say "none found — the greeter falls back to a plain dark backdrop."
  say "(drop images in $USER_HOME/.config/hypr/wallpapers/dark/ and re-run,"
  say " or pass --wallpaper /path/to/image.jpg)"
fi

# --- write the greeter -----------------------------------------------------
hdr "Installing to $ETC"

# machine.conf — everything that differs per machine, generated so the tracked
# config next to this script stays identical for everyone.
write "$ETC/machine.conf" <<EOF
# Generated by saneland's greeter/install.sh on $(date '+%Y-%m-%d %H:%M:%S').
# DO NOT EDIT — re-run \`sudo ./greeter/install.sh\` instead; every change here
# is overwritten. Source: $LOCAL_CONF
#
# Sourced from /etc/greetd/hyprland.conf.

# The screen the login window goes on. Everything else shows only wallpaper.
\$main_monitor = $MONITOR

# Your session's monitor layout, so the greeter uses the same modes, scales and
# positions (cage ran every display at its EDID-preferred mode).
${MONITOR_LINES:-# (none — the wildcard in hyprland.conf auto-detects)}

input {
${KB:-    # (no kb_* settings found in your session config)}
}
EOF

back_up "$ETC/hyprland.conf"
run install -m 644 "$SRC/hyprland.conf" "$ETC/hyprland.conf"
did "write $ETC/hyprland.conf"

back_up "$ETC/hyprpaper.conf"
run install -m 644 "$SRC/hyprpaper.conf" "$ETC/hyprpaper.conf"
did "write $ETC/hyprpaper.conf"

run install -m 755 "$SRC/greeter.sh"   "$ETC/saneland-greeter"
did "write $ETC/saneland-greeter"
run install -m 755 "$SRC/wallpaper.sh" "$ETC/saneland-greeter-wallpaper"
did "write $ETC/saneland-greeter-wallpaper"

# regreet.toml and its stylesheet go in verbatim — neither mentions the
# wallpaper. ReGreet's window is transparent (regreet.css) and hyprpaper paints
# the image behind it, so there's no path to substitute and nothing to strip
# out when there's no image to find. See the comment atop regreet.toml.
back_up "$ETC/regreet.toml"
run install -m 644 "$SRC/regreet.toml" "$ETC/regreet.toml"
did "write $ETC/regreet.toml"

back_up "$ETC/regreet.css"
run install -m 644 "$SRC/regreet.css" "$ETC/regreet.css"
did "write $ETC/regreet.css"

# A writable HOME for the greeter: its account's home is `/`, and Hyprland,
# GTK and ReGreet all want somewhere for caches and state. See greeter.sh.
GREETER_GROUP=$(id -gn "$GREETER_USER")
run install -d -o "$GREETER_USER" -g "$GREETER_GROUP" -m 700 /var/lib/greetd
did "ok    /var/lib/greetd (owned by $GREETER_USER:$GREETER_GROUP)"

# Insurance, not a requirement: with a logind seat the compositor gets its
# input devices handed over by libseat and group membership is irrelevant —
# which is why cage worked. But if that handover ever doesn't happen, a
# compositor that starts with no keyboard is a lockout you can't even Ctrl+Alt+F2
# out of, so make direct device access possible too. The greeter reads your
# keystrokes either way; that's its job.
if getent group input >/dev/null && ! id -nG "$GREETER_USER" | grep -qw input; then
  run gpasswd -a "$GREETER_USER" input
  did "ok    added $GREETER_USER to the 'input' group"
fi

# --- point greetd at it ----------------------------------------------------
# The original is kept verbatim for --uninstall, written once so re-running
# never overwrites the pre-saneland version with a saneland one.
if [[ ! -f $ETC/config.toml.saneland-orig ]]; then
  run cp -a "$ETC/config.toml" "$ETC/config.toml.saneland-orig"
  did "saved $ETC/config.toml.saneland-orig (--uninstall restores this)"
fi

if [[ $DRY == 1 ]]; then
  say "would: set [default_session] command = \"$ETC/saneland-greeter\""
else
  awk -v cmd="$ETC/saneland-greeter" '
    /^[[:space:]]*\[/ { insec = ($0 ~ /^[[:space:]]*\[default_session\][[:space:]]*$/) }
    insec && /^[[:space:]]*command[[:space:]]*=/ { next }   # drop the old command
    { print }
    /^[[:space:]]*\[default_session\][[:space:]]*$/ { print "command = \"" cmd "\"" }
  ' "$ETC/config.toml" > "$ETC/config.toml.new"
  grep -q "^command = \"$ETC/saneland-greeter\"$" "$ETC/config.toml.new" ||
    { rm -f "$ETC/config.toml.new"; die "failed to patch $ETC/config.toml — left untouched."; }
  mv "$ETC/config.toml.new" "$ETC/config.toml"
  chmod 644 "$ETC/config.toml"
  say "set   [default_session] command = \"$ETC/saneland-greeter\""
fi

# --- verify ----------------------------------------------------------------
# Better to fail here than at the next boot with no way in but a text console.
# --verify-config exits 0 either way, so the result has to be read from stdout.
hdr "Verifying"
if [[ $DRY == 1 ]]; then
  say "skipped (--dry-run)"
else
  result=$(Hyprland --verify-config --config "$ETC/hyprland.conf" 2>&1 |
           sed -n '/Config parsing result/,$p')
  if printf '%s' "$result" | grep -q 'config ok'; then
    say "ok    $ETC/hyprland.conf parses cleanly"
  else
    printf '%s\n' "$result" >&2
    die "the greeter config has errors (above). greetd still points at the new
       greeter — fix the errors, or run --uninstall, BEFORE you log out."
  fi
fi

if [[ $DRY == 1 ]]; then
  cat <<EOF

Dry run — nothing was written. Re-run without --dry-run to install the
Hyprland + ReGreet login screen: login window on $MONITOR, wallpaper on every
other screen.
EOF
  exit 0
fi

cat <<EOF

Done. The login screen is now Hyprland + ReGreet: login window on $MONITOR,
wallpaper on every other screen.

To apply it:

  sudo systemctl restart greetd     # ENDS YOUR SESSION — save your work first

Nothing changes until you do that (or reboot), so you can back out now with:

  sudo $SRC/install.sh --uninstall

If the greeter ever fails to come up, Ctrl+Alt+F2 still gets you a text
console: log in there and run the --uninstall above. The greeter's own log is
at /var/lib/greetd/.cache/hypr/ and greetd's is in \`journalctl -u greetd\`.

Re-run this script after changing monitors, wallpapers or keyboard layout —
the greeter has a copy of those, not a live view.
EOF
