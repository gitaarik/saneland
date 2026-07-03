# local/ — your overlay

This directory is your **whole-file override tree**, mirroring `config/`.
Everything you put here is git-ignored (only this README is tracked), so it
never collides with upstream — `git pull` stays clean. Point it at your own
private repo if you want to version it separately.

When `install.sh` sees `local/<app>/…`, it materialises `~/.config/<app>` as
per-file symlinks: each file is taken from `local/<app>` if it exists there,
otherwise from `config/<app>`. So you can **replace or add individual files**
without forking the whole app.

```
local/
  eww/eww.yuck        # your bar layout — overrides the base eww.yuck,
                      #   everything else in eww/ still comes from base
  swaync/config.json  # your notification behaviour
```

For *small* tweaks (keybinds, accent, extra-app theming) you usually don't need
this — use the in-place override hooks instead (`~/.config/hypr/local.conf`,
`config/eww/_local.scss`, `~/.config/saneland/theme.local.sh`).

See [../docs/CUSTOMIZING.md](../docs/CUSTOMIZING.md) for the full picture.
