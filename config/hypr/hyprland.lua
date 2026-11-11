-- ~/.config/hypr/hyprland.lua
--
-- Main Hyprland config: monitors, autostart, input, gaps, keybinds, window rules.
-- Companion files: hypridle.conf (idle/lock policy), hyprlock.conf (lock screen).
--
-- Lua since Hyprland 0.57, which removed the hyprlang `.conf` format outright
-- (hypridle and hyprlock still read hyprlang — only the compositor moved). The
-- same goes for scripts: `hyprctl dispatch` now evaluates a Lua dispatcher
-- (`hyprctl dispatch 'hl.dsp.focus({ monitor = "+1" })'`), and `hyprctl
-- keyword` is gone in favour of `hyprctl eval 'hl.config({ ... })'`.

local home = os.getenv("HOME")
local hypr = home .. "/.config/hypr/"
local bin  = "~/.local/bin/"

-- source(NAME, ...) — run ~/.config/hypr/NAME if it exists, passing it the
-- extra arguments. A missing file is fine (local.lua is optional); a file that
-- exists but fails is an error, not something to skip quietly — but it is
-- raised at the END of this file (see the bottom), not here. Raising here
-- would stop the config at that line, and a typo in local.lua would cost you
-- every keybind below it, mod+Return included.
-- loadfile rather than require: require caches, so a `hyprctl reload` after
-- `theme` flips border-colors.lua would keep the old palette.
local source_errors = {}
local function source(name, ...)
    local path = hypr .. name
    local f = io.open(path, "r")
    if not f then return end
    f:close()
    local chunk, err = loadfile(path)
    local ok = chunk ~= nil
    if ok then ok, err = pcall(chunk, ...) end
    if not ok then source_errors[#source_errors + 1] = tostring(err) end
end

-- ----------------------------------------------------------------------------
-- Monitors
-- ----------------------------------------------------------------------------
-- Format: hl.monitor({ output = NAME, mode = "RESOLUTION@REFRESH", position = "XxY", scale = S })
-- Use `hyprctl monitors` to discover names/modes.
--
-- The wildcard below is a safe default for any output (auto-detect mode and
-- position, no scaling). Put YOUR specific monitors — resolution, refresh,
-- fractional scale, arrangement — in ~/.config/hypr/local.lua (loaded from
-- the Variables section further down). Rules there override this wildcard, so
-- this base config stays generic across machines.
--
-- `preferred` means the output's EDID-preferred mode, which is NOT always its
-- best one: 4K TVs commonly prefer 3840x2160@30 while happily driving @60. The
-- symptom is a laggy cursor rather than an error, so pin the mode explicitly in
-- local.lua for any output you actually care about (see local.lua.example).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- ----------------------------------------------------------------------------
-- Environment
-- ----------------------------------------------------------------------------
-- Qt's portal platform theme reads the dark/light preference that `theme` sets
-- (org.freedesktop.appearance color-scheme). Without a platform theme Qt reports
-- "no preference", and KDE apps on their "Default" color scheme (Dolphin, …)
-- then always pick Breeze Light. Reaches apps launched after a `hyprctl reload`.
hl.env("QT_QPA_PLATFORMTHEME", "xdgdesktopportal")

-- ----------------------------------------------------------------------------
-- Autostart
-- ----------------------------------------------------------------------------
-- Lean by design — the eww bar handles the tray/system-status surface (network,
-- bluetooth, volume, battery, clock) so no separate applets are needed. Screen
-- color temp via hyprsunset; idle/lock via hypridle+hyprlock; screenshots via
-- grim+slurp (keybind further down).
--
-- `hyprland.start` fires once per session; a `hyprctl reload` re-runs this file
-- but fires `config.reloaded` instead, so nothing here gets started twice.
hl.on("hyprland.start", function()
    hl.exec_cmd("hypridle")
    hl.exec_cmd("awww-daemon")                          -- wallpaper daemon (crossfades; driven by hypr-wallpaper)
    hl.exec_cmd(bin .. "hypr-wallpaper-rotate")         -- rotate the current theme's wallpaper pool on a timer
    -- LC_TIME=en_GB.UTF-8: GtkCalendar reads first-day-of-week from the locale's
    -- first_weekday; en_GB gives Monday-first while keeping English day/month
    -- names. Needs the locale generated: uncomment en_GB.UTF-8 in
    -- /etc/locale.gen and run `sudo locale-gen`.
    -- The bar renders on EVERY monitor, one instance per screen. eww-bars.sh opens
    -- `bar` on each connected output and re-syncs on hot-plug (--watch), and it
    -- owns the LC_TIME above — its first `eww open` auto-starts the daemon (baking
    -- LC_TIME in) if none is running. Still one starter, so no `eww daemon`/`eww
    -- open` race: the two-line form could let `eww open` beat the daemon's socket
    -- bind and spawn a second daemon (→ duplicate bars).
    hl.exec_cmd("~/.config/eww/scripts/eww-bars.sh --watch")
    -- swaync is deliberately NOT started here. The packaged swaync.service is
    -- D-Bus-activated on org.freedesktop.Notifications, so an autostart line makes
    -- two starters race for one daemon. swaync claims its single-instance name
    -- (org.erikreider.swaync) about 5s BEFORE it claims org.freedesktop.Notifications
    -- — measured 12.9s vs 18.1s, and far wider during a loaded session start. A
    -- notification arriving in that gap finds the name unowned and activates the
    -- unit; that second copy then finds the instance lock taken, exits 1, and
    -- Restart=on-failure retries it forever. Each attempt is slower than the
    -- 5-starts-per-10s limiter needs to trip, so systemd never gives up: seen once
    -- as 115 restarts in ten minutes, a full core spent on GTK4 startups. So there
    -- is exactly one starter, and it is systemd:
    --     systemctl --user enable swaync.service
    hl.exec_cmd(bin .. "hypr-battery-monitor")          -- notify (swaync) on low battery (20% / 10%)
    hl.exec_cmd("hyprsunset -t 4500")
    hl.exec_cmd(bin .. "hypr-raise-focused")            -- raise focused window to top of floating z-order
    hl.exec_cmd(bin .. "hypr-max-on-open")              -- resize new non-dialog windows to work area
    hl.exec_cmd(bin .. "hypr-window-order")             -- track window creation order (for mod+Tab cycle)
    hl.exec_cmd(bin .. "hypr-alttab-daemon")            -- MRU window stack for ALT+Tab
    hl.exec_cmd(bin .. "hypr-keep-screen-focus")        -- stay on a screen whose last window just closed
    hl.exec_cmd(bin .. "hypr-notify-focus")             -- clicking a notification focuses its app's window
    hl.exec_cmd(bin .. "hypr-workspace-blocks --watch") -- pin each screen's block of 12 workspaces to it, by rank (survives a cable moving to another port)
    hl.exec_cmd(bin .. "hypr-adopt-orphans --watch")    -- unplug a screen -> its windows merge into the same tag on the one that's left
end)
-- Add your own autostarts (tray apps, etc.) in ~/.config/hypr/local.lua
-- rather than here, so this base config stays generic. Example:
--   hl.on("hyprland.start", function() hl.exec_cmd("syncthingtray-qt6 --wait") end)

-- ----------------------------------------------------------------------------
-- Input
-- ----------------------------------------------------------------------------
hl.config({
    cursor = {
        no_warps = true, -- don't warp the mouse on focus changes (e.g. taskbar clicks)
    },

    input = {
        kb_layout    = "us",
        kb_variant   = "altgr-intl",  -- AltGr dead keys: AltGr+' then e → é, etc.
        kb_options   = "ctrl:nocaps", -- Caps Lock acts as Ctrl
        follow_mouse = 2,             -- click-to-focus for keyboard; pointer/scroll follow
                                      -- the cursor, so you can scroll a hovered window
                                      -- without focusing it (cursor focus detached)
        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            disable_while_typing = true,
            scroll_factor        = 0.5, -- slow touchpad scrolling (default 1.0)
        },
    },

    misc = {
        -- New windows open on the FOCUSED MONITOR, and by default Hyprland hands
        -- that to whichever screen the mouse is over. With no_warps + follow_mouse
        -- = 2 the cursor never follows the keyboard, so the focused monitor sat on
        -- whichever screen the mouse was parked on: move focus to the second screen
        -- with mod+h/j/k/l or Alt+Tab and mod+Return still opened the terminal back
        -- on the first one. Worse, Hyprland re-derives it from the cursor after
        -- every dispatch, so focusing a monitor or window couldn't hold it there.
        --
        -- Off, the focused monitor follows the focused WINDOW: focusing a window —
        -- by key OR by click — moves it, merely hovering a screen does not. That's
        -- the same split follow_mouse = 2 already draws for keyboard focus.
        --
        -- Pointer-driven bar actions must then name their own screen rather than
        -- ask which monitor is focused; eww/scripts/hypr-scroll.sh reads the
        -- cursor's monitor for exactly this reason.
        mouse_move_focuses_monitor = false,

        -- Let an app that asks to be focused actually get focus: an
        -- xdg-activation request carrying a valid token, or _NET_ACTIVE_WINDOW
        -- under XWayland. With this off — Hyprland's default — the request
        -- only marks the window urgent (CWindow::activate). It's what brings
        -- Firefox up when another app opens a link in it.
        --
        -- Clicking a NOTIFICATION needs more than this: swaync's tokens carry
        -- no input serial, so Hyprland never grants them focus whatever this
        -- says. bin/hypr-notify-focus covers that case (see its header).
        --
        -- The cost is that an app can pull focus to itself whenever it asks.
        -- If one abuses that, opt it out with a rule instead of turning this
        -- off: hl.window_rule({ match = { class = "..." }, focus_on_activate = false }).
        focus_on_activate = true,
    },
})

-- ----------------------------------------------------------------------------
-- General appearance
-- ----------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 0,
        gaps_out    = 0,
        border_size = 2,
        -- col.active_border / col.inactive_border are theme-aware: they live in
        -- border-colors.lua, a symlink the `theme` script flips between
        -- border-colors-{dark,light}.lua alongside eww/gtk/etc. Loaded below,
        -- after this block, so the theme palette is the sole definition.
        layout = "master", -- closest in feel to awful fair

        -- Border-drag resize (no modifier needed — just grab a window border).
        -- NOTE: this is still corner-only, like every resize in Hyprland. The drag
        -- picks one of four corners from the cursor's quadrant relative to the
        -- window centre (src/layout/supplementary/DragController.cpp, dragBegin) —
        -- single-edge resize does not exist (issue #6152 closed not_planned, PR
        -- #6571 closed unmerged, confirmed on main as of 0.55.4). The hover cursor
        -- may show an edge arrow near an edge midpoint, but the actual drag still
        -- resizes a corner. extend_border_grab_area widens the otherwise 2px-thin
        -- grab zone so the border is easy to hit.
        resize_on_border        = true,
        extend_border_grab_area = 8,
    },
})

-- Theme-aware border palette (active/inactive colors). Symlink flipped by the
-- `theme` script; see border-colors-{dark,light}.lua.
source("border-colors.lua")

hl.config({
    decoration = {
        rounding = 0,
        blur = {
            enabled = true,
            size    = 4,
            passes  = 1,
        },
        shadow = {
            enabled = false,
        },
    },
})

-- Workspace slide stays — that's the only animation we like. Vertical,
-- because that is the axis workspaces actually live on here: mod+j/k walks
-- DOWN a screen's block of 12 while mod+h/l steps ACROSS to the next screen
-- (see the focus binds below). A horizontal slide contradicts the keys — you
-- press "down" and the screen moves sideways — and it spends the one
-- direction that already means "another monitor" on something else.
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "default", style = "slidevert" })

-- Everything else off. Under the stacking-first config, every animation
-- on focus change is just visual noise (the resize / fade transitions
-- produce the "flash" between the previous and next maximized window).
for _, leaf in ipairs({ "windows", "fadeIn", "fadeOut", "fade", "border", "borderangle" }) do
    hl.animation({ leaf = leaf, enabled = false })
end

-- Layer surfaces (eww bar + popups) too. Without this they inherit the
-- default `layers` animation, which popped in/out the eww "All apps"
-- pop-out as it resized (it toggles its panel with :visible, growing the
-- surface from nothing to full). 0.55's per-layer disable syntax
-- (noanim / animation none via layerrule) wouldn't take, so kill it
-- globally — consistent with everything else here being off anyway.
hl.animation({ leaf = "layers", enabled = false })

-- The magnifier is the one exception, and it is not decoration: super+scroll
-- only ever names a target factor, and setting cursor.zoom_factor assigns
-- that to an ANIMATED variable inside the compositor (each monitor's
-- m_cursorZoom, via the REFRESH_CURSOR_ZOOMS prop refresh). So this line is
-- the whole difference between the screen jumping between zoom levels and
-- gliding between them — hypr-zoom does not and cannot interpolate anything
-- itself.
--
-- Unset, the node inherits `global`, which nothing here gives a speed:
-- `hyprctl animations` reports zoomFactor at speed 0, i.e. instant.
--
-- 2 = 200ms, deliberately short. Every scroll event re-aims the goal
-- mid-flight, so the value chases the wheel; a long curve keeps travelling
-- after you stop scrolling, which reads as lag rather than as smoothness.
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 2, bezier = "default" })

hl.config({
    binds = {
        -- Hyprland default is false (fullscreen = locked focus, guard rail against
        -- accidentally popping out of a video). Tiled workflow prefers seamless
        -- cycling: focus moves AND new window inherits fullscreen state.
        movefocus_cycles_fullscreen = true,

        -- Rate-limit for scroll-wheel keybinds, default 300ms. It must be 0 here,
        -- and that is not a preference — it is what stops super+scroll from also
        -- scrolling the window under the cursor.
        --
        -- The suppression is not a drop. CKeybindManager::onAxisEvent returns
        -- `true` while the timer is unexpired, and its caller reads that return as
        -- "pass this event on", so every scroll event inside the 300ms window is
        -- handed to the surface under the cursor instead of to the bind. The bind
        -- only consumes an event it actually handles. So with the default you get
        -- one zoom step per 300ms and ALL the remaining events land in the window —
        -- exactly the symptom of the document scrolling while the screen zooms.
        --
        -- At 0 every event reaches the bind, and every event is consumed. The cost
        -- is that a high-resolution wheel fires the bind ~8-15 times per physical
        -- notch, which hypr-zoom is built for (small per-event step, coalesced
        -- writes — see the script).
        --
        -- Safe to set globally because the zoom binds are the only scroll binds
        -- here. The bar's scroll-to-switch-workspaces is an eww :onscroll handler
        -- on a layer surface, not a keybind, so it never went through this timer
        -- and keeps its own debounce in eww/scripts/hypr-scroll.sh.
        scroll_event_delay = 0,
    },

    master = {
        new_status = "slave",
        mfact      = 0.55,
    },
})

-- ----------------------------------------------------------------------------
-- Workspaces
-- ----------------------------------------------------------------------------
-- Global workspaces (Hyprland default) — workspaces follow focus between
-- monitors. When you go multi-monitor later, add `kanshi` for declarative
-- output profiles instead of pinning workspaces per output.

-- ----------------------------------------------------------------------------
-- Window rules
-- ----------------------------------------------------------------------------
-- Workflow: stacking-first DE feel ("Windows-like"). Every window floats by
-- default; combined with the maximize rule below, every new window opens
-- floating + maximized, so you see one full-screen window at a time and
-- switch between them via mod+Tab / taskbar clicks. Per-workspace taskbar
-- (eww's taskbar widget) still works regardless of float
-- state. The float-everything rule replaces the tiling master layout's
-- auto-tile behavior, and nothing is bound to togglefloating, so no window
-- ever tiles: "tiling" here is mod+Ctrl+h/j/k/l snapping a floating window to
-- half the work area. (A real tiled window would sit below every floating
-- one, which in this setup just means "hidden".)
hl.window_rule({ name = "float-everything", match = { class = "^(.*)$" }, float = true })

-- (The rule that hides the hyprbars title bar on windows tagged `nobar` lives in
-- the Plugins section: its effect only exists once hyprbars has loaded.)

-- Float-specific small dialogs (already covered by the catch-all above, but
-- kept explicit for clarity in case the catch-all is ever scoped back).
for _, class in ipairs({
    "^\\.?([Bb]lueman-manager)(-wrapped)?$",
    "^(copyq)$",
    "^(nm-connection-editor)$",
    "^(org\\.pulseaudio\\.)?([Pp]avucontrol)$",
    "^(pinentry-.*)$",
    "^(Sxiv)$",
    "^(Tor Browser)$",
    "^(.*vnc.*)$",
}) do
    hl.window_rule({ match = { class = class }, float = true })
end
hl.window_rule({ match = { title = "^(Download.*)$" }, float = true }) -- was Firefox DTA window

-- Sane initial size + center for floating dialogs. XWayland apps that don't
-- request a specific size inherit the master-layout slot size (i.e. the full
-- work area) when their float rule fires — these explicit sizes restore the
-- "small dialog" feel.
--
-- Match both spellings of each class. These rules used to say plain
-- `pavucontrol` and `[Bb]lueman-manager`, which match nothing: the real
-- Wayland app_id is org.pulseaudio.pavucontrol, and blueman comes through as
-- .blueman-manager-wrapped wherever the binary is a wrapper script. So neither
-- rule had ever fired, and pavucontrol was being opened full-screen instead.
-- (Check a class with `hyprctl clients | grep class` before trusting one.)
hl.window_rule({
    name  = "blueman-size",
    match = { class = "^\\.?([Bb]lueman-manager)(-wrapped)?$" },
    size  = "800 600",
    center = true,
})
hl.window_rule({
    name  = "pavucontrol-size",
    match = { class = "^(org\\.pulseaudio\\.)?([Pp]avucontrol)$" },
    size  = "700 500",
    center = true,
})

-- Note: some clients call set_maximized() on themselves on Wayland —
-- Thunderbird's event-details popups do it from what looks like a stale
-- "restore window state" flag. We'd block that at the protocol level with
-- a suppress_event = "maximize" rule, but there was no such windowrule field
-- in 0.56.2: it was rejected under both the old `class:` and the new
-- `match:` syntax, and nothing replaced it. (0.57's Lua rules do accept
-- suppress_event — untried here; the handler below is what's known to work.)
-- So the request reaches the compositor, and hypr-max-on-open's
-- fullscreen>>1 handler converts it into the stateless maximize used
-- everywhere else here. Since a client is free to keep asking — and one with
-- a stale flag will re-ask every time it is unmaximized — that handler backs
-- off after a few rounds and lets the window stay natively maximized rather
-- than flicker. See fight_ok there.
--
-- (The note that used to sit here described un-maximizing subsequent-of-class
-- windows at open time. That code went with commit 3f69215, when THE ONE RULE
-- made the openwindow branch skip a second window of a class outright.)

-- Stacking-first flow: new windows get sized to the work area WITHOUT
-- using the maximize/fullscreen state (Hyprland un-maximizes the previous
-- window on every focus change, which flashes during mod+Tab; plain
-- size+move via the daemon has no state to swap — just z-order. Smooth).
--
-- Sizing is owned by hypr-max-on-open: it watches openwindow events, restores
-- each class's remembered geometry, and maximizes a window only when
-- window-policy.conf lists its class as `always`. Everything else opens at the
-- size it asked for. Read the header of config/hypr/window-policy.conf for why
-- it is a list rather than a heuristic — the short version is that Hyprland
-- exposes nothing that distinguishes a dialog from a main window, so guessing
-- meant password prompts and file choosers opening full-screen.
--
-- For the same reason it only ever sizes a window that is the ONLY ONE of its
-- class: a second window of an app is usually a dialog, and no automatic sizing
-- is better than sizing GIMP's Export As to the whole screen. mod+m sizes the
-- ones it leaves alone.
--
-- Two things can't be done with a static windowrule here, which is why the
-- daemon exists at all:
--   - `size 100% 100%` is accepted by the parser but does nothing in 0.55.4
--     (measured: the window keeps its own size), and even working percentages
--     are relative to the MONITOR, so they'd sit under the 30px eww bar.
--   - absolute pixels can't serve two outputs of different sizes, and rules
--     can't match on which monitor a window opened on.
-- Trade-off for using the daemon: a one-frame visual flash on apps that would
-- otherwise have been sized before first paint.
-- mod+Shift+m still toggles real fullscreen when you want bar-covering, and
-- mod+Alt+m flips the focused window's class between `always` and `leave`.

-- ----------------------------------------------------------------------------
-- Variables
-- ----------------------------------------------------------------------------
local v = {
    mod      = "SUPER",
    term     = "kitty",
    browser  = "firefox", -- your browser of choice
    launcher = "rofi -show drun",
    lock     = "hyprlock",
    shotdir  = "~/Pictures/Screenshots",
}

-- Per-machine overrides — monitors, v.term/v.browser, extra autostarts, etc.
-- Loaded HERE: after the defaults above (so your values win) and before the
-- keybinds below (so they see your values). It gets the table above as its
-- argument and changes it in place. Git-ignored and created from
-- local.lua.example by install.sh; a missing file is harmless. Keep
-- personal/machine-specific settings there, not here.
source("local.lua", v)

local mod = v.mod

-- bind(KEYS, DISPATCHER, OPTS) with KEYS written the way the old config did:
-- modifiers space-separated, then the key — "SUPER SHIFT, Return". Saves
-- spelling `mod .. " + SHIFT + Return"` on 120 lines.
local function bind(keys, dispatcher, opts)
    local mods, key = keys:match("^%s*(.-)%s*,%s*(.-)%s*$")
    local combo = {}
    for m in mods:gmatch("%S+") do combo[#combo + 1] = m end
    combo[#combo + 1] = key
    return hl.bind(table.concat(combo, " + "), dispatcher, opts)
end

local function exec(cmd) return hl.dsp.exec_cmd(cmd) end

-- ----------------------------------------------------------------------------
-- Keybinds
-- ----------------------------------------------------------------------------
-- Translated from rc.lua key_binding_funcs. Intentionally partial — covers the
-- daily-driver set; rare binds (menu, snapshot/restore floating) come later.

-- Bar popup dismissal. Registered ONCE, here, and never touched again.
--
-- The eww popups are `:focusable false` layer-shell surfaces, so the compositor
-- will not dismiss them on focus-out the way it would a normal menu — that has to
-- be rebuilt from the outside, and these two binds are it.
--
-- They used to be armed when a popup opened and unbound when it closed, which
-- meant keeping global compositor state in sync with per-window state from
-- several short-lived scripts that ONE click starts at once (Hyprland fires the
-- bind while eww fires the widget's onclick, in no defined order). Every
-- stuck-popup bug in this system came out of that: stale binds, duplicate binds,
-- a teardown wiping a fresh arm, a ~700ms window where nothing was bound at all,
-- and menus left on screen that nothing would close. Binding once removes the
-- shared state and the whole class with it.
--
-- The cost is that both handlers now run on every left click and every Escape, so
-- each starts with a marker-file test that exits in about a millisecond when no
-- popup is open (see popup-lib.sh). non_consuming: the click still reaches
-- what is under the cursor, and Escape still reaches the focused window.
bind(", mouse:272", exec("~/.config/eww/scripts/popup-dismiss-if-outside.sh"), { release = true, non_consuming = true })
bind(", ESCAPE",    exec("~/.config/eww/scripts/popup-dismiss.sh --if-open"),  { non_consuming = true })

-- Apps
bind(mod .. ", Return",       exec(v.term))
bind(mod .. " SHIFT, Return", exec(v.browser))
bind(mod .. ", Space",        exec(v.launcher))

-- Focus. Directional, and whatever is beyond this window counts as one more
-- step in the same direction: mod+h from the leftmost window on the laptop
-- lands on the external, mod+j from the lowest window drops to the next
-- workspace on this screen. Monitors across, workspaces down — screens sit
-- side by side, and each one's block of 12 workspaces is the vertical axis, so
-- mod+h/j/k/l is one grid rather than four unrelated keys. No separate
-- workspace bind. hypr-focus-dir decides which step applies;
-- see the script for why the built-in directional focus can't (it treats
-- stacked maximized windows as neighbours, and can't reach a screen whose
-- workspace is empty).
bind(mod .. ", h", exec(bin .. "hypr-focus-dir l"))
bind(mod .. ", l", exec(bin .. "hypr-focus-dir r"))
bind(mod .. ", j", exec(bin .. "hypr-focus-dir d"))
bind(mod .. ", k", exec(bin .. "hypr-focus-dir u"))
-- The one shortcut through that grid: jump straight to the next screen,
-- landing on whatever was last focused there. mod+h/l only gets there after
-- walking past every window on this screen in that direction, and needs you to
-- know which way the other screen is. Sits above mod+Tab on purpose. Inert on a
-- single screen.
bind(mod .. ", grave", hl.dsp.focus({ monitor = "+1" }))
bind(mod .. ", Tab",       exec(bin .. "hypr-cycle-maximize"))      -- cycle next, re-apply maximize
bind(mod .. " SHIFT, Tab", exec(bin .. "hypr-cycle-maximize prev"))
-- Snap active window to a half of the work area (Mod+Ctrl+h/j/k/l).
bind(mod .. " CTRL, h", exec(bin .. "hypr-snap-window left"))
bind(mod .. " CTRL, l", exec(bin .. "hypr-snap-window right"))
bind(mod .. " CTRL, k", exec(bin .. "hypr-snap-window top"))
bind(mod .. " CTRL, j", exec(bin .. "hypr-snap-window bottom"))

-- Reorder the focused window left/right in the taskbar / cycle order
-- (manipulates ~/.cache/hypr-window-order, which eww reads).
bind(mod .. " SHIFT, h", exec(bin .. "hypr-reorder-window left"))
bind(mod .. " SHIFT, l", exec(bin .. "hypr-reorder-window right"))

-- Throw the focused window across the same grid mod+h/j/k/l navigates:
-- sideways to another screen, up/down to another workspace on this screen.
--
-- h/l is the built-in dispatcher — a `monitor = "l"` target is the monitor
-- that way, so it's a no-op with nothing there (inert on a single screen). A
-- window that was filling the screen it left is re-maximized on the one it
-- arrives at (the movewindow handler in hypr-max-on-open), so it doesn't turn
-- up wearing the other screen's dimensions.
--
-- k/j used `mon:u`/`mon:d`, which never fired on screens side by side. They
-- step the window through this screen's block of 12 instead, skipping empty
-- tags exactly as mod+k/j does — except at the end of the column, where a MOVE
-- may open the next tag (the window itself is what populates it) while a switch
-- stops. Focus stays put, matching mod+shift+<tag>.
bind(mod .. " CTRL SHIFT, h", hl.dsp.window.move({ monitor = "l" }))
bind(mod .. " CTRL SHIFT, l", hl.dsp.window.move({ monitor = "r" }))
bind(mod .. " CTRL SHIFT, k", exec(bin .. "hypr-workspace move-dir u"))
bind(mod .. " CTRL SHIFT, j", exec(bin .. "hypr-workspace move-dir d"))
-- Direction-free twin of mod+ctrl+shift+h/l, paired with mod+grave: throw the
-- window to the next screen. Same re-maximize on arrival.
bind(mod .. " SHIFT, grave", hl.dsp.window.move({ monitor = "+1" }))

-- Docked: toggle EVERY window between the external (the last screen) and the
-- laptop, each to the same tag it had, carrying the current tag and focus over
-- with them — first press makes the external the main screen, second press
-- brings it all back. Inert on a single screen. Undocking needs no key:
-- hypr-adopt-orphans merges them back into the laptop's tags.
bind(mod .. ", g", exec(bin .. "hypr-gather-windows"))

-- Window state
-- mod+M toggles maximize: first press fills work area, second press restores
-- to whatever the window's size+position was right before the first press.
-- Per-window memory in /tmp/hypr-window-prev-size.$UID.
bind(mod .. ", m", exec(bin .. "hypr-toggle-maximize"))
-- mod+SHIFT+M is real fullscreen (bar-hiding). This DOES use fullscreen state
-- and triggers the one-per-workspace rule, which is correct for video etc.
bind(mod .. " SHIFT, m", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
-- mod+ALT+M teaches the auto-maximize policy: flips the FOCUSED WINDOW'S CLASS
-- between "maximize this on open" and "open it at its own size", and says which
-- way it went in a notification. That is the intended way to correct a wrong
-- guess — window-policy.local.conf is written for you, no restart needed.
bind(mod .. " ALT, m", exec(bin .. "hypr-window-policy toggle"))
-- mod+ALT+SHIFT+M remembers the focused window's exact size and position for its
-- class, right now. hypr-max-on-open saves a geometry by itself only while an app
-- has ONE window open (so a dialog can't overwrite the real one); this is how you
-- record a size you set up with a second window of the app still on screen.
bind(mod .. " ALT SHIFT, m", exec(bin .. "hypr-window-policy remember"))
-- mod+T toggles the focused window's hyprbars title bar (the `nobar` tag that
-- hypr_chrome sets). The next snap, maximize or center re-applies that look's
-- own bar state. A bare window.tag bind doesn't redraw — see the script.
bind(mod .. ", t", exec(bin .. "hypr-toggle-titlebar"))
bind(mod .. " SHIFT, t", hl.dsp.window.pin())                        -- was: toggle on-top
-- mod+Z minimizes: hides the window on `special:min<tag>`, still listed (dimmed)
-- in that tag's taskbar and in Alt+Tab, either of which brings it back.
-- mod+SHIFT+Z restores the tag's most recently minimized window.
bind(mod .. ", z",       exec(bin .. "hypr-minimize"))
bind(mod .. " SHIFT, z", exec(bin .. "hypr-minimize restore"))
bind(mod .. ", c",       exec(bin .. "hypr-center-window"))         -- resize to ~60% + center + restore border
bind(mod .. " SHIFT, c", exec(bin .. "hypr-center-window 80"))      -- same, bigger (~80%)
bind(mod .. " CTRL, c",  exec(bin .. "hypr-center-window tall"))    -- full height, 60% wide, centered (a snap shape)
bind("CTRL SHIFT, q", hl.dsp.window.close())
-- Escalation for a hung window. window.close only asks the app to close, which a
-- frozen one ignores. window.kill SIGKILLs the focused window's process;
-- `hyprctl kill` is xkill: click the window to SIGKILL it, Escape to back out.
-- mod+shift+q is taken by the tag keys (move to tag 5), hence mod+ctrl.
bind(mod .. " CTRL, q",       hl.dsp.window.kill())
bind(mod .. " CTRL SHIFT, q", exec("hyprctl kill"))

-- Alt+Tab — MRU focus history via hypr-alttab-daemon. While Alt is held,
-- Tab walks back through previously-focused windows; Shift+Tab walks
-- forward. The cycle commits when Alt is physically released: the daemon
-- reads the real Alt key off /dev/input (needs the 'input' group — see
-- docs/ARCHITECTURE.md), so timing no longer matters. Hyprland's release
-- bind on modifier-only Alt_L release doesn't reliably fire in this build,
-- hence the evdev approach instead.
bind("ALT, Tab",       exec(bin .. "hypr-alttab next"))
bind("ALT SHIFT, Tab", exec(bin .. "hypr-alttab prev"))

-- Workspaces — 1-4 on the number row, 5-8 on qwer, 9-12 on asdf (two
-- left-hand rows reachable without leaving home position).
-- Per-screen workspaces: each number is a LOCAL tag 1..12 on the focused
-- window's screen. hypr-workspace maps it to the global workspace by the
-- monitor's rank (laptop 1-12, external 13-24); hypr-workspace-blocks pins each
-- block to its screen the same way. On a single monitor this is exactly
-- workspace 1..12.
--
-- TAG_KEYS[n] is the key for local tag n; the overview submap below uses the
-- same list, so the two can't drift apart.
local TAG_KEYS = { "1", "2", "3", "4", "q", "w", "e", "r", "a", "s", "d", "f" }
for n, key in ipairs(TAG_KEYS) do
    bind(mod .. ", " .. key, exec(bin .. "hypr-workspace switch " .. n))
end

-- Move active window to workspace (focus stays on current workspace)
-- Move the active window to a LOCAL tag on its own screen (silent = stay put).
for n, key in ipairs(TAG_KEYS) do
    bind(mod .. " SHIFT, " .. key, exec(bin .. "hypr-workspace move " .. n))
end

-- Overview (hyprexpo plugin, configured in the Plugins section below): every
-- screen shows its own block of 12 tags as a 4x3 grid of live thumbnails, laid
-- out like the keys above — 1234 / qwer / asdf — so the tile is where the key
-- is. Click a tile to switch, drag a window thumbnail onto another tile to move
-- it there, Escape or mod+x again to back out. `all` opens it on every screen
-- at once (each screen its own block); a selection on one screen closes all of
-- them and only switches that screen. x so that, like the tag keys, it is a
-- left-hand key: open, pick a tag, all without reaching across.
--
-- Plugin calls are Lua functions under hl.plugin.hyprexpo since 0.57 (the old
-- `hyprexpo:expo` dispatcher names are gone). Wrapped in a function so the
-- lookup happens on keypress, after the plugin has loaded — at parse time on
-- the first pass it hasn't yet.
local function expo(fn, ...)
    local args = { ... }
    return function() hl.plugin.hyprexpo[fn](table.unpack(args)) end
end

bind(mod .. ", x", expo("expo", "toggle all"))

-- Keys while the overview is open. The plugin enters this submap on open and
-- resets it on close, so plain keys work here: tag keys jump to that tile,
-- h/j/k/l (and the arrows) walk the grid, Return takes the focused tile. The
-- mod+ variants are the same keys with the modifier still held — mod+x, tag
-- key is one motion. Anything not listed is swallowed while it is open.
-- `kb_selecti` takes a 1-based tile POSITION, which in this fixed grid is the
-- local tag — the block offset is the screen's own, exactly like hypr-workspace.
hl.define_submap("hyprexpo", function()
    for n, key in ipairs(TAG_KEYS) do
        bind(", " .. key,          expo("kb_selecti", n))
        bind(mod .. ", " .. key,   expo("kb_selecti", n))
    end
    for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right",
                            left = "left", down = "down", up = "up", right = "right" }) do
        bind(", " .. key, expo("kb_focus", dir))
    end
    bind(", Return",   expo("kb_confirm"))
    bind(", Escape",   expo("expo", "cancel"))
    bind(mod .. ", x", expo("expo", "cancel"))
end)

-- System
bind(mod .. ", Escape", exec(v.lock))
bind(mod .. " ALT, l",  exec(v.lock))
bind(mod .. " ALT, q",  hl.dsp.exit())                                      -- quit Hyprland (back to the login manager)
bind(mod .. " ALT, r",  hl.dsp.reload_config())                             -- reload hyprland.lua
bind(mod .. " SHIFT, n", exec("swaync-client -t -sw"))                      -- toggle notification panel
bind(mod .. ", b",      exec(bin .. "hypr-wallpaper-rotate next"))          -- next wallpaper now (and restart the timer)
bind(", XF86PowerOff",  exec(bin .. "hypr-power-menu"))                     -- confirm before shutdown (needs HandlePowerKey=ignore in logind.conf)

-- Screenshots: hyprshot saves to v.shotdir AND copies to clipboard;
-- Shift variant pipes raw PNG into satty for annotation before saving.
bind(", Print",      exec("hyprshot -m region -o " .. v.shotdir))
bind("SHIFT, Print", exec("hyprshot -m region --raw | satty --filename - --output-dir " .. v.shotdir .. " --copy-command wl-copy --early-exit"))
bind("CTRL, Print",  exec("hyprshot -m output -o " .. v.shotdir))
bind("ALT, Print",   exec("hyprshot -m window -o " .. v.shotdir))

-- Media keys
bind(", XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 1%+"), { locked = true, repeating = true })
bind(", XF86AudioLowerVolume",  exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"),        { locked = true, repeating = true })
bind(", XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
bind(", XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })
bind(", XF86MonBrightnessUp",   exec(bin .. "brightness-step up"),                        { locked = true, repeating = true })
bind(", XF86MonBrightnessDown", exec(bin .. "brightness-step down"),                      { locked = true, repeating = true })

-- ----------------------------------------------------------------------------
-- Mouse
-- ----------------------------------------------------------------------------
bind(mod .. ", mouse:272",     hl.dsp.window.drag(),   { mouse = true }) -- super+left-drag to move
bind(mod .. ", mouse:273",     hl.dsp.window.resize(), { mouse = true }) -- super+right-drag to resize (grab anywhere, no need to aim at the border)
bind(mod .. " ALT, mouse:272", hl.dsp.window.resize(), { mouse = true }) -- super+alt+left-drag to resize (touchpad-friendly: no right button needed)
-- Three ways to resize, all corner-only (Hyprland has no single-edge resize —
-- see the note in the general block): the two binds above (grab anywhere in
-- the window — right-drag, or super+alt+left-drag for touchpads) and
-- general.resize_on_border (grab a window border, no modifier).

-- ----------------------------------------------------------------------------
-- Magnifier
-- ----------------------------------------------------------------------------
-- super+scroll zooms the screen the cursor is on, super+0 restores 1:1.
-- Hyprland's own cursor.zoom_factor does the work; hypr-zoom just steps it
-- multiplicatively and clamps the ends (see the script for why, and for the
-- zoom_rigid knob).
--
-- A bind consumes the event it handles, so the window under the cursor does NOT
-- also scroll — worth stating because follow_mouse = 2 means a merely-hovered
-- window normally does get the wheel. That consumption depends on
-- binds.scroll_event_delay = 0 above; at the default 300ms most events bypass
-- the bind and reach the window. Same over the bar: plain scroll there still
-- switches workspaces, super+scroll zooms instead of reaching eww.
--
-- mod+0 is the reset because the workspace keys stop at 4 on the number row
-- (5-12 live on qwer/asdf), leaving 0 free.
bind(mod .. ", mouse_up",   exec(bin .. "hypr-zoom in"))
bind(mod .. ", mouse_down", exec(bin .. "hypr-zoom out"))
bind(mod .. ", 0",          exec(bin .. "hypr-zoom reset"))

-- Same magnifier on the touchpad: super + two-finger pinch, zooming live with
-- the pinch and anchored where the cursor is.
--
-- Not a bind, because a bind cannot do this: keybind dispatch only looks at
-- scroll events whose source is a WHEEL, and touchpad scrolling is
-- source FINGER. Super+two-finger-scroll therefore never reached hypr-zoom at
-- all and went straight to the window — nothing to fix in the bind, the touchpad
-- needs its own mechanism. Hyprland has one: cursorZoom is a built-in trackpad
-- gesture (mode `live` = follow the pinch continuously; `mult`/omitted are step
-- and toggle variants, and zoom_level is the factor those two use).
--
-- mods = SUPER keeps it off apps' own pinch-zoom: gesture matching compares the
-- modifier mask exactly, so a bare two-finger pinch still belongs to Firefox,
-- image viewers and the like. Prefer it without a modifier? Use three fingers
-- (`fingers = 3`, no mods) rather than claiming plain pinch.
--
-- One seam: the gesture moves the monitor's zoom inside the compositor without
-- updating cursor.zoom_factor, and nothing exposes that internal value — not
-- even `hyprctl monitors`. So the first super+scroll notch after a pinch jumps
-- to the wheel's own idea of where the zoom was. super+0 always gets you back
-- to 1:1 whichever one you used.
hl.gesture({ fingers = 2, direction = "pinch", mods = "SUPER", action = "cursorZoom", zoom_level = "1", mode = "live" })

-- And a stepped version on a three-finger vertical swipe, no modifier: fingers
-- up zooms in, down zooms out, matching super+scroll-up = in. (Swipe direction
-- is raw finger motion — natural_scroll inverts libinput's scroll axis, not its
-- gesture deltas — so this stays "up is in" whatever the touchpad's scrolling
-- does.)
--
-- Three fingers rather than two because libinput reserves two-finger motion for
-- scrolling and only reports swipes from three up; that is also why there is no
-- two-finger-scroll version of this. No modifier is needed because gesture
-- matching compares the modifier mask exactly, so this fires only when nothing
-- is held, and vertical only, leaving left/right free for a workspace swipe.
--
-- `mult` multiplies the current zoom the moment the swipe is recognised (~5px
-- in, so a stray three-finger touch won't trigger it) — one step per swipe,
-- mid-gesture rather than on release, which is why this isn't a dispatcher
-- gesture running hypr-zoom: those fire on gesture END. It goes through the
-- same animated variable, so the step glides like the wheel's does.
--
-- 1.4 and its inverse: up-then-down lands exactly back on 1:1, because the
-- gesture clamps at 1 and 1.4 × 0.714 is a hair under it. Unlike super+scroll
-- and super+pinch, this one zooms EVERY monitor rather than the one under the
-- cursor — Hyprland's mult mode walks all of them.
--
-- Same seam as the pinch above: neither updates cursor.zoom_factor, so the next
-- super+scroll notch jumps to the wheel path's own idea of the zoom. super+0
-- still resets everything.
hl.gesture({ fingers = 3, direction = "up",   action = "cursorZoom", zoom_level = "1.4",   mode = "mult" })
hl.gesture({ fingers = 3, direction = "down", action = "cursorZoom", zoom_level = "0.714", mode = "mult" })

-- Keyboard, for when the pointer isn't where the work is: super+- / super+=
-- step out and in, held down they repeat, and super+0 (above) is 1:1 — the
-- browser's zoom trio, on the same keys.
--
-- Spelled `equal`, not `plus`: bind matching resolves the keycode through an xkb
-- state that is created fresh and never told which modifiers are down
-- (KeybindManager.cpp), so it always sees the unshifted symbol. `SUPER SHIFT,
-- plus` would therefore never fire — but SHIFT+= is what the key is labelled, so
-- it gets its own line pointing at the same place.
--
-- repeating, with a per-press step of 1.1: one tap is 10%, holding walks
-- 1:1 → 8× in about a second at the default repeat rate of 25/s. Those repeats
-- arrive 40ms apart, comfortably slower than hypr-zoom's 25ms velocity knee, so
-- a held key zooms at a constant rate instead of accelerating like a flicked
-- wheel.
--
-- Worth knowing: the magnifier is anchored to the CURSOR, not to the focused
-- window, so a keyboard zoom magnifies wherever the pointer happens to be
-- parked.
bind(mod .. ", minus",       exec(bin .. "hypr-zoom out 1.1"), { repeating = true })
bind(mod .. ", equal",       exec(bin .. "hypr-zoom in 1.1"),  { repeating = true })
bind(mod .. " SHIFT, equal", exec(bin .. "hypr-zoom in 1.1"),  { repeating = true })

-- ----------------------------------------------------------------------------
-- Plugins (hyprpm)
-- ----------------------------------------------------------------------------
-- hyprbars draws a per-window title bar with clickable close/maximize buttons — a
-- mouse/touchpad-friendly way to close a window (complements CTRL SHIFT q).
--
-- The bar shows ONLY on free-floating windows. Snapped (mod+Ctrl+h/j/k/l) and
-- maximized windows get NO bar: the window-management helper scripts tag them
-- `nobar` via hypr_chrome() (bin/hypr-window-lib.sh), and the `hyprbars:no_bar`
-- window rule below hides the bar on anything carrying that tag. Rationale: the
-- bar is drawn above the window content, so on top/maximized windows it's
-- clipped off-screen anyway, and on bottom snaps it appeared as a stray
-- mid-screen titlebar — inconsistent. Tagging makes it deterministic: bar on
-- free floats, none on snapped/maximized.
--
-- hyprexpo draws the workspace overview bound to mod+x above: a grid of live
-- thumbnails per screen. Upstream dropped it from hyprwm/hyprland-plugins in
-- May 2026; the maintained fork is sandwichfarm/hyprexpo, pinned to tagged
-- Hyprland releases.
--
-- Both are COMPILED plugins pinned to the Hyprland ABI: after every `hyprland`
-- upgrade they must be rebuilt or they silently fail to load. See
-- docs/ARCHITECTURE.md ("hyprbars") for the rebuild step. One-time install:
--     hyprpm update
--     hyprpm add https://github.com/hyprwm/hyprland-plugins
--     hyprpm enable hyprbars
--     hyprpm add https://github.com/sandwichfarm/hyprexpo
--     hyprpm enable hyprexpo
-- `hyprpm reload` loads all enabled plugins at login, AFTER this file's first
-- pass; loading a plugin makes Hyprland re-run the config. Their option keys
-- and the hyprbars:no_bar rule effect only exist once they're loaded, so
-- everything plugin-specific sits behind a loaded check: skipped on the first
-- pass instead of raising "unknown config key", applied on the re-run. If the
-- bars or the overview are missing, `hyprctl plugin list` says whether the
-- plugin loaded at all.
--
-- hyprpm itself reports through Hyprland's notification overlay, which keeps
-- nothing; bin/hypr-plugins-load runs `hyprpm reload` and puts a failure into
-- swaync instead, where the panel and the bar's bell keep it.
hl.on("hyprland.start", function() hl.exec_cmd(bin .. "hypr-plugins-load") end)

local loaded = {}
for _, p in ipairs(hl.get_loaded_plugins()) do loaded[p.name] = true end

if loaded.hyprbars then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height                 = 24,
                bar_color                  = "rgb(282828)", -- gruvbox bg
                col = { text               = "rgb(ebdbb2)" }, -- gruvbox fg
                bar_text_size              = 11,
                bar_text_font              = "JetBrainsMono Nerd Font",
                bar_button_padding         = 8,
                bar_padding                = 10,
                bar_precedence_over_border = false, -- draw the window border over the bar so the top border stays visible
                on_double_click            = bin .. "hypr-toggle-maximize", -- same as mod+m / the maximize button
            },
        },
    })

    -- Buttons render right-to-left, so close (red) ends up rightmost. Plain
    -- coloured dots, no glyph; fg_color is required by add_button all the same.
    -- hyprbars clears its buttons before every reload, so these don't pile up.
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(cc241d)", fg_color = "rgb(ebdbb2)", size = 13, icon = "",
        action   = "hyprctl dispatch 'hl.dsp.window.close()'", -- close
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(d79921)", fg_color = "rgb(ebdbb2)", size = 13, icon = "",
        action   = bin .. "hypr-toggle-maximize", -- same as mod+m
    })

    -- Hide the hyprbars title bar on any window tagged `nobar`. The window-management
    -- helper scripts (hypr_chrome in bin/hypr-window-lib.sh) add this tag to snapped
    -- and maximized windows and remove it from free-floating ones, so the bar only
    -- appears on free floats.
    hl.window_rule({ name = "nobar", match = { tag = "nobar" }, ["hyprbars:no_bar"] = true })
end

if loaded.hyprexpo then
    hl.config({
        plugin = {
            hyprexpo = {
                -- A FIXED 4x3 grid, empty tags included, so every tile sits where its
                -- key is (1234 / qwer / asdf) and `kb_selecti N` in the submap above is
                -- local tag N. skip_empty/dynamic_grid would collapse the grid to the
                -- populated tags and break that mapping.
                columns      = 4,
                rows         = 3,
                skip_empty   = 0,
                dynamic_grid = 0,

                -- Which 12 the grid shows. `center current` bounds the grid to the
                -- workspaces that exist on the screen PLUS the ids reserved for it by
                -- workspace rules naming a monitor — the very rules hypr-workspace-blocks
                -- issues at runtime. A 12-tile grid over a 12-id range is pinned to the
                -- block, so the laptop shows 1-12 and the external 13-24 without
                -- naming a connector here (a name is not a rank — see local.lua).
                workspace_method = "center current",

                -- The submap defines the digit keys itself; `workspace` mode would have
                -- the plugin read a bare `1` as GLOBAL workspace 1 on every screen.
                number_key_mode = "passthrough",

                -- Label each tile with the key that selects it, not the global id.
                label_text_mode     = "token",
                label_token_map     = table.concat(TAG_KEYS, ","),
                label_position      = "top-left",
                label_offset_x      = 10,
                label_offset_y      = 10,
                label_font_family   = "JetBrainsMono Nerd Font",
                label_font_size     = 14,
                label_font_bold     = 1,
                label_bg_shape      = "rounded",
                label_bg_color      = "rgba(282828cc)",
                label_color_default = "rgb(ebdbb2)", -- gruvbox fg, as hyprbars
                label_color_current = "rgb(d79921)", -- yellow — matches the maximize button
                label_color_focus   = "rgb(fabd2f)",
                label_color_hover   = "rgb(fbf1c7)",

                -- Chrome. The gruvbox bg behind the tiles rather than the wallpaper:
                -- thumbnails of windows over a photo were hard to read.
                bg_col               = "rgb(1d2021)",
                gaps_in              = 12,
                gaps_out             = 12,
                tile_rounding        = 6,
                border_width         = 2,
                border_color         = "rgb(3c3836)",
                border_color_current = "rgb(d79921)",
                border_color_focus   = "rgb(fabd2f)",
                border_color_hover   = "rgb(ebdbb2)",

                -- Four-finger swipe up opens it, following the finger; swipe back down
                -- or let go early to cancel. Four because three-finger up/down is the
                -- zoom step (gesture block above) and libinput reserves two for scroll.
                gesture_fingers   = 4,
                gesture_direction = "up",
                gesture_distance  = 250,
            },
        },
    })
end

-- ----------------------------------------------------------------------------
-- Debug
-- ----------------------------------------------------------------------------
-- Logs to ~/.local/share/hyprland/hyprland.log (and /tmp/hypr/<instance>/...).
-- Tail after a stuck session to find why input didn't bind.
hl.config({
    debug = {
        disable_logs = false,
    },
})

-- Errors from the files source() loaded, raised now that everything else is
-- in place, so they still reach the config-error banner.
if #source_errors > 0 then
    error(table.concat(source_errors, "\n"), 0)
end
