# Fedora.
#
# Hyprland itself is in the official repos on recent Fedora, but the wider
# hypr* ecosystem (hyprpaper/hyprlock/hypridle/hyprsunset) and eww are most
# reliably found in the solopasha/hyprland COPR — enable it first:
#
#   sudo dnf copr enable solopasha/hyprland
#
# Package names marked `# verify` weren't confirmed against a live Fedora at
# authoring time — check with `dnf search <name>` and PRs welcome.
#
# Sourced by ../deps.sh.

PM_INSTALL="sudo dnf install"

declare -A PKG=(
  [compositor]="hyprland"
  [portal-hyprland]="xdg-desktop-portal-hyprland"
  [session-uwsm]="uwsm"                       # verify
  [bar-eww]="eww"                             # COPR
  [notifications-swaync]="swaync"             # COPR
  [launcher-rofi]="rofi-wayland"              # COPR; 'rofi' in repos is X11
  [wallpaper-hyprpaper]="hyprpaper"           # COPR
  [audio-wireplumber]="wireplumber"
  [audio-pulse]="pipewire-pulse"
  [network-nm]="NetworkManager"
  [bluetooth-bluez]="bluez"
  [bluetooth-blueman]="blueman"
  [power-upower]="upower"
  [power-profiles]="power-profiles-daemon"
  [cli-jq]="jq"
  [cli-python]="python3"
  [cli-ncat]="nmap-ncat"
  [cli-brightnessctl]="brightnessctl"
  [cli-rfkill]="rfkill"                       # verify (may be in util-linux)
  [cli-libnotify]="libnotify"
  [gtk-materia]="materia-gtk-theme"           # verify (may need COPR/manual)
  [icons-papirus]="papirus-icon-theme"
  [font-jetbrains-nerd]="jetbrains-mono-fonts-all"  # verify: Nerd patch may need manual install
  [lock-hyprlock]="hyprlock"                  # COPR
  [idle-hypridle]="hypridle"                  # COPR
  [nightlight-hyprsunset]="hyprsunset"        # COPR
  [screenshot-hyprshot]="hyprshot"            # verify (may need manual)
  [annotate-satty]="satty"                    # verify (may need cargo/manual)
)
# Unmapped here (reported as "build from source / not packaged"):
#   font-adwaita — Adwaita Sans; ships with recent GNOME, else install manually.
