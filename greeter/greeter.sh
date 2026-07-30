#!/usr/bin/env bash
#
# saneland — greeter launcher. Installed to /etc/greetd/saneland-greeter and
# named as greetd's `command`; runs as the `greeter` user on VT 1.
#
# This wrapper exists for one reason: the greeter account's home directory is
# `/` (see `getent passwd greeter`), which it cannot write to. Hyprland, GTK
# and ReGreet all want somewhere to put caches and state, so we point HOME and
# the XDG dirs at /var/lib/greetd — created and chowned by greeter/install.sh —
# before handing off. Without this you get a compositor that starts but spews
# permission errors, or a GTK that falls back to defaults and ignores the theme
# set in regreet.toml.

set -euo pipefail

export HOME=/var/lib/greetd
export XDG_CACHE_HOME=/var/lib/greetd/.cache
export XDG_DATA_HOME=/var/lib/greetd/.local/share
export XDG_CONFIG_HOME=/etc/greetd

# GTK needs to know it's on Wayland; ReGreet is a GTK4 app.
export GDK_BACKEND=wayland
export XDG_CURRENT_DESKTOP=Hyprland

# exec, so greetd's child IS the compositor: when Hyprland exits (which it does
# as soon as ReGreet has handed the session over — see hyprland.conf's
# `exec-once = regreet; hyprctl dispatch exit`) greetd starts your session.
exec Hyprland --config /etc/greetd/hyprland.conf
