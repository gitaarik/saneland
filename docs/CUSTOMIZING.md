# Customizing saneland

The golden rule: **don't edit tracked files.** Put every change in a git-ignored
override so `git pull` always applies upstream updates cleanly. There are two
ways to override, by how much you're changing.

```
adjust a value / add a bit   →  Mechanism 1: in-place override hooks
replace a whole file          →  Mechanism 2: the local/ overlay
```

All of it is git-ignored, so you can keep your overrides in their own **private
repo** and have one source of truth with zero divergence from upstream.

---

## Mechanism 1 — in-place override hooks (use this first)

For the common adjustments. Each is a file the base config *includes*, so you
add to or override the defaults without touching the tracked file.

### Hyprland — `~/.config/hypr/local.lua`
Lua (Hyprland 0.57 dropped the `.conf` format). Loaded after the base defaults
and before the keybinds, so your values win; it receives the base config's
table of defaults as `local v = ...`. `install.sh` seeds it from
`local.lua.example`. Put here:

- **Monitors** — `hl.monitor({ output = "eDP-1", mode = "2256x1504@60", position = "0x0", scale = 1.5666667 })`
- **App/var overrides** — `v.browser = "chromium"`, `v.term = "alacritty"`
- **Extra keybinds / rules / autostarts** — just add `hl.bind(…)`, `hl.window_rule({…})`,
  `hl.on("hyprland.start", function() hl.exec_cmd("…") end)`
- **Change what a base keybind runs** — set the `v.*` value it reads
  (`v.term`, `v.browser`, `v.launcher`, `v.lock`). The base keybinds are
  defined *after* local.lua runs, so an `hl.unbind` here would be undone by
  them; rebinding a base key to something else entirely means editing
  `hyprland.lua`.

### eww bar styling — `config/eww/_local.scss`
Imported by `_eww-common.scss`. The active theme's palette (`$bg`, `$fg`,
`$accent`, `$accent-tint`, …) is already defined, so reassign those or set the
font vars:

```scss
$accent: #b16286;
$accent-tint: rgba(177, 98, 134, 0.25);
$font-family: "Inter", sans-serif;
$font-size: 13px;
```

### Theming extra apps — `~/.config/saneland/theme.local.sh`
saneland's `theme` script themes only the desktop shell (eww, swaync, GTK,
KDE/Qt apps, rofi, wallpaper). To theme *your* terminal / editor too, copy
`~/.config/saneland/theme.local.sh.example` to `theme.local.sh`. It's sourced
at the end of `theme` with `$COLOR_SCHEME` ("dark"/"light") set — plain shell,
do whatever your apps need. (Apps that just read `~/.cache/current-theme`, like
fzf and lsd, need nothing — `theme` already wrote it.)

---

## Mechanism 2 — the `local/` overlay (whole-file replace)

For things with no include mechanism — most importantly the **bar layout**
(`eww.yuck`) and **swaync behaviour** (`config.json`).

Drop a file into `local/<app>/<same path>` and `install.sh` uses it instead of
the base one, symlinking the app per-file (`local/` wins, base fills the rest):

```
local/eww/eww.yuck        # your bar layout; the rest of eww/ stays base
local/swaync/config.json  # your notification rules
local/hypr/hyprlock.conf  # your lock screen — e.g. pinning the clock and the
                          #   password box to one monitor instead of drawing a
                          #   copy on every screen. hyprlock has no `source =`,
                          #   so this is its only override mechanism.
```

Re-run `./install.sh` after adding an overlay file.

**The trade-off, stated plainly:** a file you overlay is now *yours* — you stop
getting upstream changes to that one file (you still get updates to every file
you didn't overlay). So prefer Mechanism 1 where it can express the change; reach
for the overlay only for structural edits. When you do overlay a file, it's
worth occasionally diffing it against the base to pull in upstream fixes by hand:

```bash
diff local/eww/eww.yuck config/eww/eww.yuck
```

---

## Keeping your overrides in a private repo

Everything above is git-ignored in saneland. To version it, make the override
locations a private repo and symlink them in — e.g.:

```bash
# ~/dev/saneland-local is your private repo
ln -s ~/dev/saneland-local/hypr-local.lua    ~/dev/saneland/config/hypr/local.lua
ln -s ~/dev/saneland-local/eww-local.scss    ~/dev/saneland/config/eww/_local.scss
ln -s ~/dev/saneland-local/theme.local.sh    ~/.config/saneland/theme.local.sh
ln -s ~/dev/saneland-local/local             ~/dev/saneland/local
```

Now `saneland` tracks the base, `saneland-local` tracks *you*, and updating is
`git pull` in each — no forks, no merge conflicts.
