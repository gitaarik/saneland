# Architecture & gotchas

The design notes that aren't obvious from reading the configs — mostly things
that cost real debugging time.

## Session startup (uwsm / portals)

Hyprland is launched via **uwsm** from the login manager. The wrapper matters:
it activates `graphical-session.target`, which `xdg-desktop-portal` and its
backends (`-hyprland`, `-gtk`) gate on via `Requisite=`. Without uwsm the
portal never starts and GTK/Electron apps don't receive live theme changes
from `gsettings`. Log into the "Hyprland (uwsm-managed)" session.

## The eww bar

- Launched from `hyprland.conf` (`eww daemon` + `eww open bar`). Layout is
  `eww.yuck`; shared styling in `_eww-common.scss`, per-theme palettes in
  `eww-{dark,light}.scss` selected via the `eww.scss` symlink (flipped by
  `theme`). Reload with `eww reload`.
- The workspace switcher (`tag`/`tags`) and per-workspace taskbar
  (`taskbar`/`task`) are both driven by `scripts/hypr-state.sh`, which reads
  the **`hypr-window-order` daemon's** state file. That daemon (started from
  `hyprland.conf`) is what keeps window order stable instead of letting it
  reshuffle on focus — the taskbar is not self-contained without it.

## Systray popups: no keyboard grab, one-click switching

Every popup window (`start-popup` + audio/network/bluetooth/battery/clock)
sets **`:focusable false`** — deliberately no keyboard grab.

`:focusable true` maps to gtk-layer-shell's *exclusive* keyboard mode. That
grab broke one-click popup switching: with a popup open, the first click on
another systray icon was spent breaking the grab, so the click-outside
dismiss closed the open popup but the click never reached eww's button — the
new popup only opened on a *second* click. Dropping the grab lets the click
hit the bar immediately.

Because there's no grab, switching can't rely on a click reaching the bar
alone: **`popup-toggle.sh` closes any other open popup synchronously before
opening the new one**, using the live `eww active-windows` list as ground
truth (which also self-heals if a race ever left two popups open).

Escape routes are all grab-independent and armed by `popup-toggle.sh`:

1. **Esc** — a *global* `hyprctl bind` that Hyprland evaluates before key
   delivery regardless of focus (eww has no key handler of its own).
2. **Click outside** — a `bindrn` on `mouse:272` (release, non-consuming) →
   `popup-dismiss-if-outside.sh`, which checks the cursor against the popup's
   layer-shell bounds so clicks *inside* the popup don't dismiss it.
3. **Focus change** — a `hypr` events-socket listener that dismisses when
   another window gains focus.

`popup-dismiss.sh` tears the temporary Esc/mouse binds back down. Never open a
popup with a bare `eww open` (arms none of this) — always go through
`popup-toggle.sh`.

> **eww 0.5.0 quirk:** `:focusable` is a *boolean*. The string enum
> (`"exclusive"`/`"ondemand"`) silently fails to render the surface — the
> popup just doesn't appear. So the on-demand keyboard mode that would give
> focus *without* an exclusive grab isn't available until eww is upgraded.

## Alt-Tab (MRU)

`hypr-alttab-daemon` keeps a most-recently-used window stack so holding Alt and
tapping Tab walks back through focus history. The cycle "commits" (reorders the
MRU) the instant **Alt is physically released** — the daemon reads the real Alt
key straight off `/dev/input/event*` (raw, no python-evdev dependency).

**This requires membership in the `input` group.** Without it the daemon can't
open the keyboard device and falls back to a timer whose guesses are exactly
what makes MRU order feel "mixed up". Hyprland's `bindr` on `Alt_L` release was
tried first but doesn't fire reliably in this build.

Empty workspaces are part of the MRU too: switching to an empty desktop pushes a
`ws:<id>` sentinel, so Alt-Tab toggles between an empty desktop and the last
window like it toggles two windows.

## `hyprctl` from a stale shell

`hyprctl` targets a compositor via `$HYPRLAND_INSTANCE_SIGNATURE`, captured at
process start. If Hyprland restarts under a long-lived shell the signature goes
stale and every `hyprctl` fails with "Couldn't connect to …/.socket.sock".
Resolve the live one with **`hyprsig`** (reads `hyprctl instances`, which needs
no signature):

```bash
eval "$(hyprsig -x)"                                  # fix the current shell
HYPRLAND_INSTANCE_SIGNATURE=$(hyprsig) hyprctl …      # one-off
```

## Theme system

`theme dark|light` switches the desktop-shell apps at once with a
**symlink-swap**: each app keeps `config-dark.<ext>` and `config-light.<ext>`
and a `config.<ext>` symlink pointing at the active one. `theme` flips the
symlinks and reloads each daemon — eww (full restart, see below), swaync, rofi.

GTK is handled differently: dark links a settings/CSS override, light removes
it (falling back to the system light theme), and `gsettings` sets the
color-scheme / theme / icon set so portal-aware apps (Firefox, Thunderbird,
file dialogs) follow along. It uses `prefer-light` rather than `default` so the
portal exposes `org.freedesktop.appearance color-scheme = 2` — apps like Qt
6.5+ and Telegram treat `0` ("no preference") as "don't change" and would
otherwise stay dark.

The eww restart is required because eww 0.5 caches its CSS provider for the
daemon's lifetime — `eww reload` re-reads the SCSS but window background colors
stick, so `theme` does a full `eww kill` + `eww open bar` (detached via
`setsid -f`).

The active theme is also written to `~/.cache/current-theme` for anything else
you want to follow it.

## Wallpapers (hyprpaper 0.8.4)

Per-theme image pools live in `~/.config/hypr/wallpapers/{dark,light}/`.

- `hypr-wallpaper [scheme]` picks a random image from that pool and applies it,
  avoiding an immediate repeat.
- `hypr-wallpaper-rotate` is a flock singleton timer (started from
  `hyprland.conf`) that re-runs `hypr-wallpaper` every interval for whatever
  theme is active, and paints once at login.
- `theme` calls `hypr-wallpaper "$scheme"` on each switch to repaint at once.

> **hyprpaper 0.8.4 quirk:** the hyprtoolkit rewrite ignores `wallpaper=` /
> `preload` in `hyprpaper.conf` and dropped the `preload`/`unload`/`listloaded`
> IPC subcommands. Only `hyprctl hyprpaper wallpaper ,<path>` works (it
> auto-loads the image). So `hyprpaper.conf` only turns IPC on; everything else
> goes through the helper scripts.

## hyprbars

Hyprland draws no title bars by default. The `plugin { hyprbars { … } }` block
adds a per-window bar with clickable close/maximize buttons (touchpad-friendly
window closing).

The bar shows **only on free-floating windows** — snapped and maximized windows
get none. The bar renders above the window content, so on top/maximized windows
(the eww bar reserves the *bottom* edge, `RES_TOP = 0`) it clips off the top of
the screen anyway, and on bottom snaps it used to appear as a stray mid-screen
titlebar. To make it deterministic, the window-management helpers tag snapped
and maximized windows `nobar` (via `hypr_chrome` in `bin/hypr-window-lib.sh` —
the `max` and `snap` looks add the tag, the `normal` look removes it), and this
windowrule hides the bar on anything carrying it:

```
windowrule = hyprbars:no_bar 1, match:tag nobar
```

So: bar on free floats (dialogs, `mod+c` center), no bar on snapped
(`mod+Ctrl+h/j/k/l`) or maximized windows.

It's a **compiled plugin pinned to the Hyprland ABI** — after every `hyprland`
upgrade it silently fails to load until rebuilt:

```bash
hyprpm update    # re-sync headers to the new Hyprland, rebuild plugins
hyprpm list      # confirm hyprbars is enabled
```

`exec-once = hyprpm reload -n` in `hyprland.conf` loads enabled plugins at
login. Button glyphs need JetBrainsMono Nerd Font.

## Electron secret storage

Electron apps pick their `--password-store` backend from
`XDG_CURRENT_DESKTOP`, which is `Hyprland` here — a string Electron doesn't
recognize, so it falls back to `basic_text` (encryption key stored obfuscated
in a plain file). Force the backend in the launcher instead, e.g. a user
desktop override with `Exec=… --password-store=gnome-libsecret`, for any
Electron app that stores secrets.
