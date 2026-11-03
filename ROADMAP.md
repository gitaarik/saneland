# Roadmap

Planned work, roughly in priority order. Bug reports and ideas are welcome as
[issues](https://github.com/gitaarik/saneland/issues).

## Keyboard control for the bar

The systray popups take no keyboard focus today. In eww 0.5 `:focusable` is a
boolean, and `true` means an exclusive keyboard grab, which broke one-click
switching between popups (see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#systray-popups-no-keyboard-grab-one-click-switching)).
Newer eww releases have an on-demand mode that gives focus without the grab.

- [ ] Move to a newer eww, re-testing every popup against one-click switching
      and click-outside dismiss.
- [ ] Arrow keys and Enter inside the popups: audio devices, Wi-Fi networks,
      Bluetooth devices, the start menu.
- [ ] Keybinds that open the start menu and each systray popup.

## Tests and CI

About 10,000 lines of Bash and Python, and nothing checks them automatically
yet.

- [ ] ShellCheck on every push (GitHub Actions).
- [ ] Unit tests for the logic that needs no running compositor: the
      per-screen workspace-block arithmetic (and that `hypr-workspace`,
      `hypr-state.sh` and `hypr-scroll.sh` agree on it), `sun-phase`'s tzdata
      coordinate parsing, the window-policy matching, and `deps.sh`'s package
      mapping.

## Install and uninstall

- [ ] `install.sh --uninstall`: remove the symlinks and put the
      `*.bak-<timestamp>` backups back, as `greeter/install.sh --uninstall`
      already does for the login screen.
- [ ] Seed `config/eww/_local.scss` from an example and git-ignore it, like
      `local.yuck`, so restyling the bar can't conflict with `git pull`.

## Distro support

- [ ] Fedora: check the package names marked `# verify` in `deps/fedora.sh`
      against a live install.
- [ ] Debian/Ubuntu: document, or script, building eww and ReGreet from
      source, since neither is packaged there.

## Releases

- [ ] A `CHANGELOG.md` alongside the tagged releases (v0.1.0 is the first),
      so changes can be followed without reading the commit log.
