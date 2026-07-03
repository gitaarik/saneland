# Canonical dependency manifest for saneland — distro-AGNOSTIC logical IDs.
#
# This is the single source of truth for "what saneland needs". Each
# deps/<distro>.sh maps these IDs to that distro's real package name(s).
# To add a dependency: add an ID here (+ a DEP_DESC line), then map it in
# every distro module. An ID a module doesn't map is reported as
# "build from source / not packaged".
#
# Sourced by ../deps.sh — not meant to be run directly.

CORE_DEPS=(
  compositor portal-hyprland session-uwsm
  bar-eww notifications-swaync launcher-rofi wallpaper-hyprpaper
  audio-wireplumber audio-pulse network-nm
  bluetooth-bluez bluetooth-blueman power-upower power-profiles
  cli-jq cli-python cli-ncat cli-brightnessctl cli-rfkill cli-libnotify
  gtk-materia icons-papirus font-adwaita font-jetbrains-nerd
)

# Only affect their own binding/autostart if absent — see README.
OPTIONAL_DEPS=(
  lock-hyprlock idle-hypridle nightlight-hyprsunset
  screenshot-hyprshot annotate-satty
)

declare -A DEP_DESC=(
  [compositor]="Hyprland Wayland compositor"
  [portal-hyprland]="xdg-desktop-portal backend for Hyprland"
  [session-uwsm]="uwsm session wrapper (activates graphical-session.target)"
  [bar-eww]="eww — the status bar"
  [notifications-swaync]="SwayNotificationCenter"
  [launcher-rofi]="rofi launcher (Wayland build)"
  [wallpaper-hyprpaper]="hyprpaper wallpaper daemon"
  [audio-wireplumber]="WirePlumber (wpctl)"
  [audio-pulse]="PipeWire-Pulse (pactl)"
  [network-nm]="NetworkManager (nmcli)"
  [bluetooth-bluez]="BlueZ + tools (bluetoothctl)"
  [bluetooth-blueman]="Blueman pairing UI"
  [power-upower]="UPower (battery info)"
  [power-profiles]="power-profiles-daemon"
  [cli-jq]="jq"
  [cli-python]="Python 3"
  [cli-ncat]="ncat (socket bridge for the popups)"
  [cli-brightnessctl]="brightnessctl"
  [cli-rfkill]="rfkill"
  [cli-libnotify]="libnotify (notify-send)"
  [gtk-materia]="Materia GTK theme"
  [icons-papirus]="Papirus icon theme"
  [font-adwaita]="Adwaita Sans font"
  [font-jetbrains-nerd]="JetBrainsMono Nerd Font"
  [lock-hyprlock]="hyprlock lock screen"
  [idle-hypridle]="hypridle idle daemon"
  [nightlight-hyprsunset]="hyprsunset color temperature"
  [screenshot-hyprshot]="hyprshot screenshots"
  [annotate-satty]="satty screenshot annotation"
)

# Minimum versions of the fast-moving components whose config syntax we depend
# on. Cross-distro, an older packaged build can silently break configs — deps.sh
# surfaces these so users can check. (Advisory; not auto-enforced.)
declare -A MIN_VERSION=(
  [compositor]="0.45"   # hyprland — rule syntax, plugin ABI
  [bar-eww]="0.5"       # :focusable is a boolean; string enum silently fails
  [wallpaper-hyprpaper]="0.8"  # IPC-only wallpaper apply
)
