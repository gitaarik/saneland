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

- Launched from `hyprland.conf` via `eww-bars.sh --watch`, which opens one bar
  per monitor and re-syncs the set on hot-plug. Layout is `eww.yuck`; shared
  styling in `_eww-common.scss`, per-theme palettes in `eww-{dark,light}.scss`
  selected via the `eww.scss` symlink (flipped by `theme`). Reload with
  `eww reload`.
- **Exactly one eww daemon, brought up before any `eww open`.** eww auto-starts
  a daemon for any command that finds no server, so opening N bars in a loop
  from a cold start races N daemons into existence — the first hasn't bound the
  socket by the time the second looks. Each ends up owning one bar, only the
  last to bind is reachable, and `eww close` can never reach the others. Their
  bars survive every sync, and when a monitor is unplugged gtk-layer-shell
  simply moves the orphaned surface onto a remaining screen: two stacked bars,
  `reserved` doubled to 60. `ensure_daemon` in `eww-bars.sh` starts the daemon
  once and waits for `eww ping`, and kills a running-but-unreachable daemon
  first (its surfaces are unreachable too, so nothing else ever cleans them
  up). Check with `ss -xlp | grep eww` — more than one listener is this bug.
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

## Closing the last window on a screen

Hyprland picks what to focus after an unmap by looking at the **cursor**, not at
the keyboard. With `cursor:no_warps = true` the pointer sits wherever it was last
left, so closing the last window on the second screen throws focus back to
whichever monitor the mouse happens to be parked over — and the next mod+Return
opens a terminal *there* instead of on the empty screen you're looking at.

`misc:mouse_move_focuses_monitor = false` does **not** cover this. That stops a
mouse *move* from taking the focused monitor; this refocus is Hyprland's own and
runs whether or not the mouse moved at all.

`bin/hypr-keep-screen-focus` puts it back. Only the *last* window of a screen is
affected — close one of several and Hyprland focuses a sibling on the same
monitor — so the fix keys off a two-event signature rather than a state query:

```
closewindow>>ADDR         the window is gone
focusedmon>>NAME,WS       ...and focus left the screen entirely
```

Nothing else emits that pair back to back, so seeing it *is* the detection: the
daemon dispatches `focusmonitor` at the screen it was tracking before the close.
That leaves the monitor focused with **no window focused**, which Hyprland
handles fine — `hypr-focus-dir` already depends on that state when mod+h/l steps
onto an empty second screen.

Two guards, both about hot-plug: the target connector must still exist, and the
workspace it is *currently showing* must really be empty (the screen may still
hold windows on another tag, and that must not block the restore).

It's a daemon rather than a wrapper around the `killactive` bind because windows
also close via the hyprbars close button and from inside the app (Ctrl+W,
File→Quit), and all of those should behave the same.

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

## Killable event loops

Several daemons here follow Hyprland's event socket. The obvious shape is
wrong:

```bash
ncat -U "$sock" | while IFS= read -r line; do …; done   # DON'T
```

`kill <daemon>` then does one of two bad things. With no trap installed the
main shell dies immediately but `ncat` and the loop subshell are orphaned and
**keep running** — measured: a test daemon in this shape went on appending
output after its main pid was gone, so a "stopped" `hypr-raise-focused` would
still be dispatching `alterzorder` on every focus change. With a trap installed
it is worse: bash defers a trapped signal until the current foreground command
finishes, and a pipeline of external commands never gets interrupted, so the
signal is swallowed outright and only `kill -9` (or killing the whole process
group, so `ncat` gets it too and the pipeline ends on its own) works.

Read from a fd instead:

```bash
exec 3< <(ncat -U "$sock")
ncat_pid=$!                       # bash ≥5.1 sets $! for a process substitution
trap 'kill $ncat_pid 2>/dev/null' EXIT
trap 'exit' INT TERM              # a signal trap that does not exit just resumes
while IFS= read -r line <&3; do … done
```

The shell now blocks in the `read` **builtin**, which a signal does interrupt,
and the loop runs in the main shell rather than a subshell — one process fewer
and any state it keeps lives where the rest of the script can see it. Used by
`hypr-max-on-open`, `hypr-window-order`, `hypr-raise-focused`,
`hypr-keep-screen-focus`, `hypr-state.sh` and `eww-bars.sh --watch`.

`popup-toggle.sh` deliberately keeps the pipeline form: its listener is a
one-shot that exits from inside the loop on the first `activewindow`, and the
comment there explains why the close action has to be inline. It installs no
trap, so a `kill` of the backgrounded subshell works; the orphaned `ncat` reaps
itself on its next write.

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

## Auto-maximizing new windows

`bin/hypr-max-on-open` listens on Hyprland's event socket and decides how big a
new window should be. In order:

1. **`never`** in the policy (below) — don't touch it, don't remember it.
2. **Not the only window of its class** — don't touch it. See "one window at a
   time" below; this is the rule the rest of the section keeps referring back
   to.
3. **Remembered geometry** for the class *on the screen it opened on*, from
   `~/.cache/hypr-window-state/<class>.json`. This wins over the policy: it is a
   decision you already made about this exact app. See "one geometry per
   screen" below.
4. **`always`** in the policy — maximize to the work area of the monitor the
   window opened on.
5. Otherwise the window keeps the size it asked for.

The policy is data, not code: `config/hypr/window-policy.conf` (tracked,
generic app families) and `window-policy.local.conf` (git-ignored, this
machine). `mod+Alt+m` flips the focused window's class between `always` and
`leave`; `hypr-window-policy show|list|forget|remember` covers the rest.

**One window at a time.** Automatic sizing — the restore, the maximize *and* the
saving — only ever applies to a window that is the only one of its class at that
moment (`alone_of_class`). A second window of an app is a dialog far more often
than it is a second main window: GIMP's Preferences and Export As, Thunderbird's
event details, a browser's Picture-in-Picture and Library.

This one rule replaced two mechanisms that both tried to answer "is this a main
window?" and both had to be taught app by app: a per-app title classifier
(`classify_by_title`, which knew about browser and Thunderbird titles) and a
"did it open at ≥60% of the work area" size test. Neither could scale — the
classifier needed a new arm for every app, and the size test is blind to a large
dialog. GIMP made both fail at once: every window it opens is app-id `gimp`, so
its remembered full-screen geometry was being applied to every dialog it
showed, and Preferences is ~70% of the laptop work area, big enough to pass the
size test too.

The cost is that a second window of an app that doesn't remember its own size
opens small. `mod+m` sizes that window, and `mod+Alt+Shift+m`
(`hypr-window-policy remember`) records a geometry for the class deliberately —
which is also the answer to the one thing the old classifier did better: a
browser's size used to be saved unconditionally, even with sibling windows open,
because the classifier could tell a browsing window from an `Extension: …`
popup. Now saving waits for the app's last window, or for you to ask.

Nothing you do by hand is gated: `mod+m`, `mod+c`, the snaps, an app's own
maximize button and moving a window between screens all act on whatever window
you point them at.

**Why a list and not a heuristic.** There is no way to ask a Wayland client
whether it is a dialog. `hyprctl clients` exposes no parent window, no window
type and no size hints; `xdgTag` and `contentType` are in the JSON but
`match:xdgTag` is rejected as an invalid windowrule field (0.55.4); and the X11
answers (`_NET_WM_WINDOW_TYPE`, `WM_TRANSIENT_FOR`, `WM_NORMAL_HINTS`) only
exist for XWayland windows. This config used to maximize the first window of
every class, which is why password prompts and file choosers came up
full-screen.

**Why a daemon and not a windowrule.** `size 100% 100%` parses but does nothing
in 0.55.4, and percentages are relative to the *monitor*, so they would ignore
the 30px eww bar; absolute pixels can't serve two outputs of different sizes,
and rules can't match on which monitor a window opened on. The cost is a
one-frame flash on apps that would otherwise be sized before first paint.

**A geometry has to be re-asserted, not just applied.** Under xdg-shell a
configure for a window that is neither maximized nor fullscreen is a
*suggestion* — the client may commit whatever size it likes. A window that is
still sizing itself when the geometry lands therefore keeps only the part it
had already finished with. Firefox-family browsers restore `sizemode=maximized`
plus a stored size from their profile and grow through several sizes in the
first ~250ms, so a browser that was closed maximized came back **full height
and short in width** (measured on Waterfox: asked 1440x930, got 1190x930 — the
height taken, the width discarded). `apply_and_settle` re-checks and re-applies
on a 0.15/0.35/0.7/1.2s schedule, stopping at the first check that matches, so
a client that simply obeys costs one extra `hyprctl clients`. The same loop is
what distinguishes a slow starter from a client that will never comply.

Two self-corrections keep the list small:

- **Refused maximizes are learned.** A client with fixed size constraints
  (`resizable=false`, so `min_size == max_size`) silently keeps its own size —
  Hyprland then reports the client's real geometry, not the box it was handed.
  When that happens (still under 90% of the work area after `apply_and_settle`
  has used up every retry) the class is demoted to `leave` in the local file so
  it never flashes again. It won't overwrite a rule you wrote yourself.
- **Geometry is persisted on resize, not just on close.** Hyprland's event
  socket has no resize event, so the 2s clients poll doubles as the change
  detector: a new geometry is written once it has held still for two ticks — and
  only while it is the app's only window, the same gate as everywhere else (the
  poll counts the class in its own snapshot, so this costs no extra query).
  A window you never touch is never written from there — it still goes through
  the close-time path, which only saves the last window of a class.
- **…except while the monitors are settling.** Unplug an output and Hyprland
  moves every workspace on it to a surviving screen, resizing the windows to
  fit. To the poller that is indistinguishable from you resizing them, so a
  dock cycle used to overwrite the remembered geometry of everything that got
  shuffled — measured: kitty and Telegram lost their half-screen snaps on the
  second monitor and came back remembered as full-screen on the laptop. A
  `monitoradded`/`monitorremoved` event now touches a marker file, and for the
  next 5s the poller *adopts* each new geometry as its baseline instead of
  writing it (so nothing is written when the window closes either), and the
  close-time save is skipped as well.

**One remembered geometry per screen.** A size in pixels means different things
on different monitors, so one number per class cannot serve two of them. With a
single entry (schema v2), a browser closed maximized on the 1440-wide laptop
reopened 1440 wide on the 1920-wide Dell; maximizing it there wrote 1920 back
for every screen, which the laptop then clamped to 1440 on the next open and
saved again — a permanent ping-pong in which neither screen was ever right.

Schema v3 keys the geometry by connector name and records the work area it was
measured in:

```json
{"v": 3, "last": "eDP-1", "mons": {
  "eDP-1": {"width": 1440, "height": 930, "x": 0, "y": 0, "aw": 1440, "ah": 930},
  "DP-2":  {"width": 954, "height": 1044, "x": 963, "y": 3, "aw": 1920, "ah": 1050}}}
```

A window opening on a screen it has been on before gets that screen's own
geometry, and closing it there writes only that screen's entry. On a screen it
has *never* been on, the most recent entry is reinterpreted for this one by
`reanchor_axis`, which is what `aw`/`ah` are for: they turn "1440 px wide" back
into "as wide as the screen". Per axis, each edge of the saved geometry is
matched against the work-area boundaries and the midline; if both land on one,
the geometry is rebuilt from this screen's equivalents, keeping whatever inset
it had — which reproduces `hypr-snap-window`'s 3px border exactly, so a right
half on the Dell reopens as a right half on the laptop. (That inset is also why
the tolerance here is 8px and not `geom_tolerance`: a snapped half is
`work_w/2 - 6` wide and still means "half".)

An edge matching nothing is a size you dialled in by hand, and that is meant
literally — a window you shrank to 900px wants to be 900px on the 4K screen
too, not 60% of it. Only its position is remapped, proportionally to the free
space around it, so a centred window stays centred and one parked against an
edge stays there.

v2 files are still read and are upgraded the next time the window is saved — no
cache wipe. But "the next save" can be a long way off, because a geometry is
only written when the class has one window left: a terminal or a chat app you
always keep one window of stays v2 for as long as you keep it open, and kitty
went on opening laptop-sized on the Dell long after the browser had sorted
itself out. So a v2 entry's screen is inferred instead — a
geometry must have *fit* on the monitor it was saved on, so the smallest
connected work area it fits in is the candidate, which for the case that
matters (something saved filling its screen) is exact. The guess can be wrong
for a window that merely happens to be laptop-sized on the Dell, and that is
fine: it is legacy data, replaced by a real v3 entry the first time it saves.

`hypr-window-policy show <class>` prints one line per screen.

**A maximized window stays maximized when it changes screen.** Moving a window
doesn't resize it, so one maximized on the laptop arrives on the Dell still
1440x930, with a band of desktop down two sides, and one maximized on the Dell
arrives on the laptop 1920x1050, hanging off the edges. The `movewindow` handler
gives it the new screen's work area instead, so `mod+Ctrl+Shift+h/j/k/l` keeps
it looking maximized in both directions — including shrinking it back on the way
to the smaller screen.

Nothing has to be tracked to know it was maximized, because *maximized* here **is
a work area**: mod+m applies a geometry, not a state (`hypr_fills_work_area`), so
a window wearing some **other** connected screen's work area was maximized there
a moment ago, and that alone is the signal. `.monitor` is already the destination
when the event arrives — verified by querying on the event itself — so there is
no address→monitor map to keep either. A window that fills the screen it just
landed on is left alone, which covers every move that stayed on one monitor
(`mod+Shift+<tag>`) and every move between two screens of the same size; so are
tiled windows, which the layout re-tiles anyway, and real fullscreen, which
Hyprland re-applies per monitor.

Only a *full* work area counts. A half-screen snap carried to another monitor
keeps its old pixels — `reanchor_axis` knows how to re-read those for a
different screen, but only at open time.

It is a handler on the event rather than a wrapper around the two move binds
because Hyprland posts `movewindow` from the one function that reassigns a
window's workspace, so dragging a window across the monitor boundary goes
through it too.

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
