# Arch Linux / derivatives (EndeavourOS, CachyOS, …).
#
# Most of the stack is in the official repos; a few live in the AUR (listed in
# AUR_DEPS) and need an AUR helper. Repo-vs-AUR placement drifts over time — if
# pacman can't find a package, check the AUR (and vice-versa) with
# `pacman -Si <pkg>` / your AUR helper.
#
# Sourced by ../deps.sh.

PM_INSTALL="sudo pacman -S --needed"
AUR_INSTALL="paru -S --needed"          # change to `yay -S --needed` if you use yay

declare -A PKG=(
  [compositor]="hyprland"
  [portal-hyprland]="xdg-desktop-portal-hyprland"
  [session-uwsm]="uwsm"
  [bar-eww]="eww"
  [notifications-swaync]="swaync"
  [launcher-rofi]="rofi-wayland"
  [wallpaper-hyprpaper]="hyprpaper"
  [audio-wireplumber]="wireplumber"
  [audio-pulse]="pipewire-pulse"
  [network-nm]="networkmanager"
  [bluetooth-bluez]="bluez bluez-utils"
  [bluetooth-blueman]="blueman"
  [power-upower]="upower"
  [power-profiles]="power-profiles-daemon"
  [cli-jq]="jq"
  [cli-python]="python"
  [cli-ncat]="nmap"                     # provides ncat
  [cli-brightnessctl]="brightnessctl"
  [cli-rfkill]="util-linux"             # rfkill ships in util-linux (base)
  [cli-libnotify]="libnotify"
  [gtk-materia]="materia-gtk-theme"
  [icons-papirus]="papirus-icon-theme"
  [font-adwaita]="adwaita-fonts"
  [font-jetbrains-nerd]="ttf-jetbrains-mono-nerd"
  [lock-hyprlock]="hyprlock"
  [idle-hypridle]="hypridle"
  [nightlight-hyprsunset]="hyprsunset"
  [screenshot-hyprshot]="hyprshot"
  [annotate-satty]="satty"
)

# IDs served from the AUR (installed via AUR_INSTALL, not pacman). Verify — the
# extra/AUR line moves; some of these land in extra periodically.
AUR_DEPS=(bar-eww launcher-rofi gtk-materia screenshot-hyprshot annotate-satty)
