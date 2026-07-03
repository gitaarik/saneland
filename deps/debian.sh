# Debian / Ubuntu — BEST-EFFORT.
#
# Honest warning: the Hyprland stack is bleeding-edge and poorly packaged on
# Debian/Ubuntu. eww is not packaged (build with cargo), and Hyprland is often
# absent or too old to match saneland's config syntax (see MIN_VERSION in
# manifest.sh). Expect to build several components from source or use upstream
# release binaries. The IDs not mapped below are reported as "build from
# source / not packaged".
#
# Only the genuinely-packaged, distro-agnostic bits are mapped here.
#
# Sourced by ../deps.sh.

PM_INSTALL="sudo apt install"

declare -A PKG=(
  [audio-wireplumber]="wireplumber"
  [audio-pulse]="pipewire-pulse"
  [network-nm]="network-manager"
  [bluetooth-bluez]="bluez"
  [bluetooth-blueman]="blueman"
  [power-upower]="upower"
  [power-profiles]="power-profiles-daemon"
  [cli-jq]="jq"
  [cli-python]="python3"
  [cli-ncat]="ncat"
  [cli-brightnessctl]="brightnessctl"
  [cli-rfkill]="rfkill"
  [cli-libnotify]="libnotify-bin"
  [icons-papirus]="papirus-icon-theme"
  [font-jetbrains-nerd]="fonts-jetbrains-mono"   # NOT the Nerd-patched build; install that manually
)
# Build from source / upstream (not mapped above):
#   compositor, portal-hyprland, session-uwsm, bar-eww, notifications-swaync,
#   launcher-rofi, wallpaper-hyprpaper, lock-hyprlock, idle-hypridle,
#   nightlight-hyprsunset, screenshot-hyprshot, annotate-satty, gtk-materia,
#   font-adwaita
