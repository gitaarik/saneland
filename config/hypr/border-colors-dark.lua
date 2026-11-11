-- Border palette — DARK theme.
--
-- Active pops: a light chrome sheen (light→mid gray, 45° bevel) reads clearly
-- against the dark wallpaper. Inactive recedes: a dark neutral that melts into
-- the dark background so unfocused frames stay quiet.
--
-- The light theme (border-colors-light.lua) is the near-mirror of this: the
-- active/inactive lightness flips so the active border always contrasts with
-- the background and the inactive one always blends in.
hl.config({
    general = {
        col = {
            active_border   = { colors = { "rgba(eaeaeaff)", "rgba(9a9a9aff)" }, angle = 45 },
            inactive_border = "rgba(44443eff)",
        },
    },
})
