-- Border palette — LIGHT theme.
--
-- Mirror of border-colors-dark.lua. Active pops: a dark gunmetal sheen
-- (dark→mid gray, 45° bevel) reads clearly against the light wallpaper.
-- Inactive recedes: a light neutral that melts into the light background so
-- unfocused frames stay quiet — the opposite lightness of the dark palette,
-- which is what keeps "active = most noticeable" true on either theme.
hl.config({
    general = {
        col = {
            active_border   = { colors = { "rgba(3c3c3cff)", "rgba(707070ff)" }, angle = 45 },
            inactive_border = "rgba(cfcfcfff)",
        },
    },
})
