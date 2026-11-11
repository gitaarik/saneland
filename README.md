# saneland

*Sane defaults for a modern Wayland desktop — old-school simple window
management, new-school underneath.*

saneland turns [Hyprland](https://hyprland.org) into a complete desktop:

- a custom **eww bottom bar**: workspace switcher, per-workspace taskbar, and a
  systray (audio, network, bluetooth, battery, clock) with one-click popups;
- **small daemons** for what a bare compositor leaves to you: MRU Alt-Tab,
  window order that stays put, windows that reopen where you left them, and
  windows that survive a monitor being unplugged;
- a one-command **light/dark theme switch** that repaints the whole session.

**Who it's for:** people who like what Hyprland is underneath but want a
traditional desktop on top — floating windows, a taskbar, Alt-Tab, maximize
and snap — without assembling it themselves. Arch Linux is the main target;
Fedora is supported and Debian/Ubuntu is best-effort (see
[Distro support](#distro-support)).

**Built with:** Bash and Python scripts (no build step),
[eww](https://github.com/elkowar/eww) for the bar, and Hyprland's own config.
The only compiled parts are two optional Hyprland plugins, hyprbars and
hyprexpo.

**Status:** saneland is my daily desktop.

<video src="https://github.com/user-attachments/assets/2fdd4273-38a7-4636-9558-31a910b05617" controls muted width="100%"></video>

---

## Features

- **eww bottom bar** replacing waybar — reactive, scriptable, themeable.
- **Per-workspace taskbar** driven by a small window-order daemon, so window
  order is stable (not reshuffled on focus).
- **Systray with popups** for audio, network (wifi list + connect), bluetooth
  (paired devices, connect/disconnect), battery (health, profile) and a
  clock/calendar — each opens on a single click and switches cleanly to
  another popup on the next click.
- **Start menu** popup with pinned apps + a rofi "all apps" fallback, and
  inline confirmation for power actions.
- **One-command theming** — `theme dark` / `theme light` flips the eww bar,
  swaync, GTK, KDE/Qt apps, rofi and the wallpaper together via a symlink-swap
  pattern.
- **Wallpaper rotation** with per-theme image pools, crossfading between images
  (awww) — plus `wallpaper-fetch` to fill an empty pool from Wikimedia Commons,
  sorting each image into its pool by measuring it rather than trusting its
  category.
- **Wallpapers that follow the sun** — four pools in one brightness ladder
  (`dark → dusk → dawn → light`). Your theme picks which end you live at, and
  the sun's actual elevation (`sun-phase`) moves you one rung towards the middle
  near the horizon. The theme itself never changes on its own.
- **Windows that reopen where you left them** — each app comes back at its last
  size and position on that screen (KWin-style), and a per-app policy decides
  which ones open maximized (`mod+Alt+m` flips it for the focused window).
- **Quality-of-life Hyprland scripts** — MRU Alt-Tab, window snapping /
  centering / maximize-toggle, minimize and restore, title bars toggled per
  window, scroll-to-switch workspaces, a workspace overview, a desktop
  magnifier on super+scroll, super+-/+ or a touchpad pinch / three-finger
  swipe, brightness & battery helpers.
- **No windows lost to a hot-plug** — unplug a screen and its windows merge
  into the same-numbered desktop on the screen that's left, instead of
  stranding themselves on desktops no key can reach. Plug it back in and they
  go home.

## Repository layout

```
config/          # → ~/.config/*  (whole-dir symlinks)
  eww/           # the bar: eww.yuck, modules/ (widgets), styles/ + per-theme SCSS, scripts/
  hypr/          # hyprland.lua, hyprlock.conf, hypridle.conf, window-policy.conf
  swaync/        # notification daemon (theme-integrated)
  rofi/          # launcher — the start menu's "all apps" fallback (theme-integrated)
  gtk-3.0/ gtk-4.0/   # GTK app theming, so Firefox/dialogs follow light/dark
  saneland/      # the theme hook example + the KDE color schemes `theme` applies
bin/             # → ~/.local/bin/*  (per-file symlinks): the daemons, hypr-* helpers, theme …
greeter/         # → /etc/greetd  (OPTIONAL, needs root): the login screen
local/           # your whole-file overrides, git-ignored (see docs/CUSTOMIZING.md)
wallpapers/      # image pools dark/ dusk/ dawn/ light/ — your own, or run wallpaper-fetch
deps/            # per-distro package maps for deps.sh
docs/            # ARCHITECTURE.md (design notes & gotchas), CUSTOMIZING.md
deps.sh          # installs the dependencies for your distro
install.sh       # symlinks everything into place (backs up what's there)
```

## Dependencies

Core (required):

`./deps.sh` maps this canonical list to your distro's package names and offers
to install them (`./deps.sh --print` to just see the plan). The list itself:

| Purpose            | Package(s) |
|--------------------|------------|
| Compositor         | `hyprland`, `uwsm`, `xdg-desktop-portal-hyprland` |
| Bar                | `eww` (0.5.x) |
| Notifications      | `swaync` |
| Launcher           | `rofi` (wayland fork) |
| Audio              | `wireplumber` (`wpctl`) + `pipewire-pulse` (`pactl`) |
| Network            | `networkmanager` (`nmcli`) |
| Bluetooth          | `bluez`, `bluez-utils` (`bluetoothctl`), `blueman` |
| Battery/power      | `upower`, `power-profiles-daemon` |
| GTK theme/icons    | `materia-gtk-theme`, `papirus-icon-theme` (the names `theme` sets via gsettings — swap in the script for others) |
| Misc CLI           | `jq`, `python`, `nmap` (`ncat`), `brightnessctl`, `rfkill`, `libnotify` |
| Wallpaper          | `awww` ≥0.12 (the renamed `swww`; binaries are `awww`/`awww-daemon`) |
| Fonts              | `ttf-adwaita`/Adwaita Sans, `ttf-jetbrains-mono-nerd` |

Optional (referenced by `hyprland.lua` — each only affects its own
binding/autostart if missing):

- `hyprlock` + `hypridle` — lock screen & idle policy
- `hyprbars` — window title bars (compiled plugin, see below)
- `hyprexpo` — workspace overview on `mod+x` (compiled plugin, see below)
- `hyprsunset` — night-light color temperature (autostarted)
- `hyprshot` + `satty` — screenshot capture & annotation (Print-key binds)
- `imagemagick` — only for `wallpaper-fetch`, which measures candidate images

### Distro support

The configs and scripts are distro-agnostic (they're just files in `~/.config`
and `~/.local/bin`) — only *dependency installation* differs per distro, and
that's isolated in `deps/`:

- **Arch** — first-class (repos + a few AUR packages).
- **Fedora** — supported via the `solopasha/hyprland` COPR (a few package names
  still want verifying — PRs welcome).
- **Debian/Ubuntu & others** — best-effort. The Hyprland stack is bleeding-edge
  and thinly packaged here, so expect to build `eww`/Hyprland from source;
  `deps.sh` installs what *is* packaged and lists the rest. Mind the minimum
  versions (`deps/manifest.sh`) — an older packaged Hyprland/eww can break the
  configs.

Adding a distro is just a new `deps/<distro>.sh` mapping the IDs in
`deps/manifest.sh` — no changes to the core.

## Install

```bash
git clone https://github.com/gitaarik/saneland.git
cd saneland
./deps.sh             # install dependencies for your distro (or --print)
./install.sh          # symlink configs + scripts (--dry-run to preview)
```

`install.sh` symlinks `config/*` into `~/.config/` and `bin/*` into
`~/.local/bin/`, backing up anything already there to `*.bak-<timestamp>`. It
also creates the default (dark) active-theme symlinks and seeds the local
override files (see [Personalize](#personalize)) from their examples, never
clobbering existing ones.

Then:

1. **Alt-Tab MRU** needs raw keyboard access — add yourself to `input`:
   ```bash
   sudo usermod -aG input "$USER"   # then log out and back in
   ```
2. **hyprbars** (window title bars with close/maximize buttons) and
   **hyprexpo** (the `mod+x` workspace overview) are compiled plugins pinned
   to the Hyprland ABI — install once, rebuild after every Hyprland upgrade:
   ```bash
   hyprpm update
   hyprpm add https://github.com/hyprwm/hyprland-plugins
   hyprpm enable hyprbars
   hyprpm add https://github.com/sandwichfarm/hyprexpo
   hyprpm enable hyprexpo
   ```
   (hyprexpo comes from the sandwichfarm fork: upstream dropped it from
   hyprland-plugins in May 2026.)
3. Drop wallpapers into `wallpapers/dark/` and `wallpapers/light/` (`dusk/`
   and `dawn/` are optional) — or, for a cold start, `wallpaper-fetch` pulls
   freely-licensed nature photography from Wikimedia Commons and sorts it into
   the pools by measured luminance (see `wallpapers/README.md`).
4. Log into the **Hyprland (uwsm-managed)** session (the uwsm wrapper is what
   activates `graphical-session.target`, which the desktop portals gate on),
   or in a running session: `hyprctl reload && eww reload`.

## Login screen (optional)

Everything above stays inside your home directory. The login screen can't —
it runs before you log in, as another user — so it's a separate, opt-in script:

```bash
sudo ./greeter/install.sh          # --dry-run first if you like
sudo systemctl restart greetd      # applies it; ENDS YOUR SESSION
```

Needs `greetd`, `regreet` and `hyprpaper` — the last one paints the login
screen's single static image, which is why it's still a dependency even though
the session itself now uses `awww`.

It replaces greetd's usual `cage -s -- regreet` with a stripped-down Hyprland
running the same ReGreet UI. The reason is multi-monitor: cage welds every
output into one surface (`-m extend`), so the login box lands on the seam
between two screens, and its only alternative (`-m last`) picks whichever
output was connected last and blanks the others. Under Hyprland the login
window goes on **one** screen and the rest show the wallpaper — and each
display gets the mode and scale from your `local.lua` instead of whatever
its EDID prefers (a 4K TV that asks for 30Hz would otherwise render the
greeter at 30Hz).

Your monitor layout, keyboard layout and wallpaper are **copied** to
`/etc/greetd` at install time, not read live — the greeter user can't see your
home. Re-run the script after changing any of them. It picks the internal
panel as the login screen by default; `--monitor DP-1` overrides that, and
`--uninstall` restores the greeter you had before.

If the login box comes out bigger than you'd like, the knob is the scale, not
the font: ReGreet's box is a fixed number of logical pixels wide, so a smaller
`font_name` only shrinks the text inside it. Set `v.greeter_scale` in
`local.lua` (or pass `--scale`) to drive the login screen at its own scale —
every other display keeps your session's. Hyprland wants a scale that divides
the mode into whole logical pixels, so the values on offer depend on the panel:
2256x1504 takes `1.3333333` or `1`, but rejects `1.25`.

## Theming

```bash
theme dark
theme light
```

Each app keeps `config-dark.<ext>` and `config-light.<ext>` files plus a
`config.<ext>` symlink pointing at the active one; `theme` swaps the symlinks
and nudges each daemon to reload. The active theme is also recorded in
`~/.cache/current-theme` for anything else you want to follow it.

GTK is the exception: dark links a settings/CSS override, light removes it to
fall back to the system light theme, and `gsettings` drives portal-aware apps
(Firefox, Thunderbird, file dialogs) via the Materia theme + Papirus icons.

## Personalize

Machine-specific settings live in **local override files**, kept apart from
the tracked base config so it stays identical for everyone and `git pull`
never clobbers your tweaks. Full guide:
**[docs/CUSTOMIZING.md](docs/CUSTOMIZING.md)**. The short version:

- **`~/.config/hypr/local.lua`** (seeded from `local.lua.example`) — your
  **monitors**, `v.term`/`v.browser`, and extra autostarts. It's
  loaded after the base defaults, so your values win. This is the main
  place you'll edit.
- **`~/.config/hypr/window-policy.local.conf`** — which apps open maximized,
  ahead of the defaults in `window-policy.conf`. `mod+Alt+m` and
  `hypr-window-policy` write it for you.
- **`~/.config/eww/local.yuck`** — which browser the Start menu launches.
- **`config/eww/_local.scss`** — override the bar's **accent color and fonts**
  (reassign `$accent`/`$accent-tint`, set `$font-family`/`$font-size`). The
  exception: a missing SCSS import is a hard error, so this one ships tracked,
  as a comment-only stub, and you edit it in place.

The first three are git-ignored and seeded by `install.sh`. Everything else is
opinionated-but-editable in the tracked files:

- **Keybinds & window rules** — the `bind(…)`/`hl.window_rule(…)` blocks in
  `hyprland.lua`.
- **Start-menu pins** — the `start-item` rows in
  `config/eww/modules/start-menu.yuck`.
- **Wallpaper rotation interval** — top of `bin/hypr-wallpaper-rotate`; the
  crossfade between images is the `TRANSITION` line in `bin/hypr-wallpaper`.

## How it works / gotchas

The non-obvious bits — why popups grab (or don't grab) the keyboard, how the
MRU Alt-Tab reads `/dev/input`, why the wallpaper daemon isn't hyprpaper, the stale
`HYPRLAND_INSTANCE_SIGNATURE` trap, and more — are documented in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Roadmap

What's planned next — keyboard control for the bar, tests and CI, an
uninstaller, better Fedora and Debian support — is in
[ROADMAP.md](ROADMAP.md).

## License

[MIT](LICENSE), except the two Breeze color schemes in
`config/saneland/kde-colors/`: those are copies of KDE's own files and stay
under [LGPL-2.0-or-later](LICENSES/LGPL-2.0-or-later.txt). Contributions
welcome.
