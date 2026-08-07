#!/usr/bin/env bash
#
# saneland — paint the greeter's wallpaper. Installed to
# /etc/greetd/saneland-greeter-wallpaper, run from the greeter's hyprland.conf.
#
# The session has ~/.local/bin/hypr-wallpaper for this; the greeter can't use
# it (different user, no access to your home, no theme cache) and doesn't want
# to — that one drives awww to crossfade between a rotating pool, while this
# paints one static image once and is gone. So hyprpaper it is, with its quirk:
# 0.8.4 ignores the `wallpaper =` directive in its config file and only
# responds to `hyprctl hyprpaper wallpaper ,<path>` over IPC.
# The empty monitor field means "all outputs", including the one holding the
# login window: ReGreet's window is transparent (regreet.css), so this is the
# picture you see behind it — the greeter has no background of its own.
#
# The image is a single file copied to /usr/share/backgrounds by
# greeter/install.sh (world-readable: the greeter user can't read your home).

wallpaper=/usr/share/backgrounds/saneland-greeter

# Resolve whatever extension install.sh used.
for f in "$wallpaper".*; do
    [[ -r $f ]] && { wallpaper=$f; break; }
done
[[ -r $wallpaper ]] || exit 0

# Wait for hyprpaper's IPC: at startup, monitor and EGL setup takes a few
# seconds before the daemon accepts connections, and hyprctl just prints
# "failed to connect" until it does. 20s is far longer than it has ever needed.
for _ in $(seq 1 40); do
    [[ "$(hyprctl hyprpaper listactive 2>&1)" != *"failed to connect"* ]] && break
    sleep 0.5
done

hyprctl hyprpaper wallpaper ",$wallpaper" &>/dev/null
