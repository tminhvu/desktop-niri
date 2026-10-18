#!/usr/bin/env bash

set -Eeuo pipefail

DRY_RUN=false
SKIP_PACKAGES=false
NERD_FONTS_VERSION="3.5.1"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [--dry-run] [--skip-packages]

Install this Niri desktop setup on Ubuntu 26.04 or newer.

Options:
  --dry-run        Print intended actions without changing the machine.
  --skip-packages  Deploy configuration without installing packages or fonts.
  -h, --help       Show this help.
EOF
}

for argument in "$@"; do
  case "$argument" in
    --dry-run) DRY_RUN=true ;;
    --skip-packages) SKIP_PACKAGES=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  printf 'Run this script as your normal user, not as root. It will request sudo when needed.\n' >&2
  exit 1
fi

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$STATE_HOME/niri-dotfiles-backups/$STAMP"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

log() {
  printf '\n==> %s\n' "$*"
}

note() {
  printf '  %s\n' "$*"
}

run() {
  if $DRY_RUN; then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

require_source() {
  if [[ ! -e "$1" ]]; then
    printf 'Required repository file is missing: %s\n' "$1" >&2
    exit 1
  fi
}

backup_existing() {
  local target="$1"
  local relative backup_target

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return
  fi

  relative="${target#/}"
  backup_target="$BACKUP_DIR/$relative"
  note "Backing up $target to $backup_target"
  run mkdir -p -- "$(dirname -- "$backup_target")"
  run mv -- "$target" "$backup_target"
}

link_config_directory() {
  local name="$1"
  local source="$REPO_DIR/$name"
  local target="$CONFIG_HOME/$name"

  require_source "$source"
  if [[ -L "$target" && "$(readlink -f -- "$target")" == "$source" ]]; then
    note "$target is already linked"
    return
  fi

  backup_existing "$target"
  run mkdir -p -- "$CONFIG_HOME"
  run ln -s -- "$source" "$target"
}

install_user_file() {
  local source="$1"
  local target="$2"
  local mode="${3:-0644}"

  require_source "$source"
  if [[ -f "$target" ]] && cmp -s -- "$source" "$target"; then
    note "$target is already current"
    return
  fi

  backup_existing "$target"
  run mkdir -p -- "$(dirname -- "$target")"
  run install -m "$mode" -- "$source" "$target"
}

render_template() {
  local source="$1"
  local target="$2"
  local rendered="$TEMP_DIR/$(basename -- "$target").rendered"

  require_source "$source"
  sed "s|@HOME@|$HOME|g" "$source" > "$rendered"
  install_user_file "$rendered" "$target"
}

check_supported_os() {
  if [[ ! -r /etc/os-release ]]; then
    printf 'Cannot identify this operating system. Use --skip-packages after installing dependencies manually.\n' >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ ${ID:-} != "ubuntu" ]]; then
    printf 'Automatic package installation currently supports Ubuntu 26.04+.\n' >&2
    printf 'On %s, install the listed dependencies first, then run: ./setup.sh --skip-packages\n' "${PRETTY_NAME:-this distribution}" >&2
    exit 1
  fi

  if ! dpkg --compare-versions "${VERSION_ID:-0}" ge "26.04"; then
    printf 'Ubuntu 26.04 or newer is required for the supported DMS/Niri packages.\n' >&2
    exit 1
  fi
}

install_packages() {
  log "Installing Ubuntu packages"
  check_supported_os

  run sudo apt-get update
  run sudo apt-get install -y software-properties-common ca-certificates curl jq xz-utils dconf-cli
  run sudo add-apt-repository -y universe
  run sudo add-apt-repository -y ppa:avengemedia/danklinux
  run sudo add-apt-repository -y ppa:avengemedia/dms
  run sudo apt-get update
  run sudo apt-get install -y \
    niri dms matugen waybar fuzzel swaybg swaylock xwayland-satellite \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
    wireplumber brightnessctl pavucontrol power-profiles-daemon network-manager-gnome \
    xfce4-terminal lxpolkit \
    fcitx5 fcitx5-bamboo fcitx5-frontend-all fcitx5-frontend-gtk2 fcitx5-config-qt \
    python3 python3-evdev libnotify-bin fonts-noto fonts-noto-mono fonts-font-awesome
}

install_iosevka_nerd_font() {
  local detected archive font_dir

  detected="$(fc-match 'Iosevka Nerd Font Mono' -f '%{family}' 2>/dev/null || true)"
  if [[ "$detected" == *"Iosevka Nerd Font Mono"* ]]; then
    note "Iosevka Nerd Font Mono is already installed"
    return
  fi

  log "Installing Iosevka Nerd Font Mono $NERD_FONTS_VERSION"
  archive="$TEMP_DIR/Iosevka.tar.xz"
  font_dir="$DATA_HOME/fonts/IosevkaNerdFont"
  run curl --fail --location --retry 3 \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v$NERD_FONTS_VERSION/Iosevka.tar.xz" \
    --output "$archive"
  run mkdir -p -- "$font_dir"

  if $DRY_RUN; then
    note "Extract the Regular, Medium, SemiBold, and Bold Mono faces into $font_dir"
  else
    tar -xJf "$archive" -C "$font_dir" \
      IosevkaNerdFontMono-Regular.ttf \
      IosevkaNerdFontMono-Medium.ttf \
      IosevkaNerdFontMono-SemiBold.ttf \
      IosevkaNerdFontMono-Bold.ttf
    fc-cache -f "$font_dir"
  fi
}

install_user_configs() {
  log "Linking primary desktop configurations"
  link_config_directory niri
  link_config_directory waybar
  link_config_directory fuzzel
  link_config_directory matugen
  require_source "$REPO_DIR/niri/window-memory.py"
  note "Window memory starts with either Niri session; saved rules in $CONFIG_HOME/niri-window-memory are preserved"

  log "Installing wallpaper and generated Fuzzel fallback"
  install_user_file "$REPO_DIR/wallpapers/wall-2.png" "$HOME/Pictures/wall-2.png"
  if [[ ! -f "$CACHE_HOME/niri-desktop/fuzzel-colors.ini" ]]; then
    install_user_file "$REPO_DIR/fuzzel/dank-colors.ini" "$CACHE_HOME/niri-desktop/fuzzel-colors.ini"
  else
    note "$CACHE_HOME/niri-desktop/fuzzel-colors.ini already exists; preserving generated colors"
  fi

  log "Installing Xfce Terminal, GTK, and font rendering settings"
  install_user_file \
    "$REPO_DIR/desktop-config/xfce4-terminal.xml" \
    "$CONFIG_HOME/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
  install_user_file "$REPO_DIR/desktop-config/gtkrc-2.0" "$HOME/.gtkrc-2.0"
  install_user_file "$REPO_DIR/desktop-config/gtk-3.0/gtk.css" "$CONFIG_HOME/gtk-3.0/gtk.css"
  install_user_file "$REPO_DIR/desktop-config/gtk-3.0/settings.ini" "$CONFIG_HOME/gtk-3.0/settings.ini"
  install_user_file "$REPO_DIR/desktop-config/gtk-4.0/settings.ini" "$CONFIG_HOME/gtk-4.0/settings.ini"
  install_user_file \
    "$REPO_DIR/desktop-config/fontconfig/20-no-embedded.conf" \
    "$CONFIG_HOME/fontconfig/conf.d/20-no-embedded.conf"

  log "Installing Fcitx 5 Bamboo configuration"
  install_user_file \
    "$REPO_DIR/desktop-config/fcitx5/config" \
    "$CONFIG_HOME/fcitx5/config"
  install_user_file \
    "$REPO_DIR/desktop-config/fcitx5/profile" \
    "$CONFIG_HOME/fcitx5/profile"
  install_user_file \
    "$REPO_DIR/desktop-config/fcitx5/conf/bamboo.conf" \
    "$CONFIG_HOME/fcitx5/conf/bamboo.conf"
}

install_dms_config() {
  log "Installing DMS theme, bar settings, and wallpaper state"
  install_user_file "$REPO_DIR/dms/niri-blue.json" "$CONFIG_HOME/DankMaterialShell/niri-blue.json"
  render_template "$REPO_DIR/dms/settings.json.template" "$CONFIG_HOME/DankMaterialShell/settings.json"
  render_template "$REPO_DIR/dms/session.json.template" "$STATE_HOME/DankMaterialShell/session.json"
}

install_system_integration() {
  local keyd_target="/etc/keyd/default.conf"
  local dms_workspace="/usr/share/quickshell/dms/quickshell/Modules/DankBar/Widgets/WorkspaceSwitcher.qml"

  log "Installing the second login session"
  run sudo install -m 0755 "$REPO_DIR/sessions/niri-session-dms" /usr/local/bin/niri-session-dms
  run sudo install -m 0644 "$REPO_DIR/sessions/niri-dms.desktop" /usr/share/wayland-sessions/niri-dms.desktop

  log "Retiring the former managed keyd swap"
  # Only retire our exact old rule; preserve unrelated keyd configurations.
  if [[ -f "$keyd_target" ]] && cmp -s "$keyd_target" <(printf '[ids]\n*\n-36ae:fe9c\n\n[main]\ncapslock = esc\nesc = capslock\n'); then
    run sudo systemctl disable --now keyd
    run sudo mv -- "$keyd_target" "$keyd_target.niri-dotfiles.bak.$STAMP"
  fi

  log "Installing SDINNO keyboard chatter filter (40 ms)"
  local source target mode
  for source in chatter-filter-linux.py chatter-filter.service uinput.conf; do
    case "$source" in
      chatter-filter-linux.py) target=/usr/local/bin/chatter-filter-linux.py; mode=0755 ;;
      chatter-filter.service) target=/etc/systemd/system/chatter-filter.service; mode=0644 ;;
      uinput.conf) target=/etc/modules-load.d/chatter-filter-uinput.conf; mode=0644 ;;
    esac
    require_source "$REPO_DIR/system/chatter-filter/$source"
    if [[ -f "$target" ]] && cmp -s "$REPO_DIR/system/chatter-filter/$source" "$target"; then
      note "$target is already current"
    else
      if [[ -e "$target" ]]; then
        run sudo cp -a -- "$target" "$target.niri-dotfiles.bak.$STAMP"
      fi
      run sudo install -m "$mode" "$REPO_DIR/system/chatter-filter/$source" "$target"
    fi
  done
  run sudo modprobe uinput
  run sudo systemctl daemon-reload
  run sudo systemctl enable --now chatter-filter.service
  run sudo systemctl restart chatter-filter.service

  log "Applying compact DMS workspace pills"
  if [[ ! -f "$dms_workspace" ]]; then
    printf 'DMS workspace source not found at %s\n' "$dms_workspace" >&2
    exit 1
  fi

  if grep -Fq '(isActive ? 16 : 12)' "$dms_workspace"; then
    note "DMS workspace pill patch is already applied"
  elif $DRY_RUN; then
    note "Patch DMS workspace pills to 16 px active and 12 px inactive"
  else
    sudo cp -a -- "$dms_workspace" "$dms_workspace.niri-dotfiles.bak.$STAMP"
    sudo sed -E -i \
      's#(^[[:space:]]*readonly property real baseWidth:.* : )\(isActive \? .*$#\1(isActive ? 16 : 12)#' \
      "$dms_workspace"
    if ! grep -Fq '(isActive ? 16 : 12)' "$dms_workspace"; then
      printf 'The installed DMS version has changed and the workspace patch did not apply.\n' >&2
      printf 'Original file preserved at %s.niri-dotfiles.bak.%s\n' "$dms_workspace" "$STAMP" >&2
      exit 1
    fi
  fi
}

validate_installation() {
  log "Validating configuration"

  jq -e . "$REPO_DIR/dms/niri-blue.json" >/dev/null
  jq -e . "$REPO_DIR/dms/settings.json.template" >/dev/null
  jq -e . "$REPO_DIR/dms/session.json.template" >/dev/null

  if command -v niri >/dev/null 2>&1; then
    niri validate -c "$REPO_DIR/niri/config.kdl"
    niri validate -c "$REPO_DIR/niri/config-dms.kdl"
    note "Both Niri sessions validate"
  elif ! $DRY_RUN; then
    printf 'niri was not installed successfully.\n' >&2
    exit 1
  fi

  if command -v fuzzel >/dev/null 2>&1 && [[ -f "$CACHE_HOME/niri-desktop/fuzzel-colors.ini" ]]; then
    fuzzel --check-config --config "$REPO_DIR/fuzzel/fuzzel.ini"
    note "Fuzzel configuration validates"
  fi

  bash -n "$REPO_DIR/setup.sh"
  note "Installer syntax validates"
}

main() {
  log "Niri desktop setup from $REPO_DIR"
  $DRY_RUN && note "Dry-run mode: no changes will be made"

  if ! $SKIP_PACKAGES; then
    install_packages
    install_iosevka_nerd_font
  else
    note "Skipping package and font installation"
  fi

  install_user_configs
  install_dms_config
  install_system_integration
  validate_installation

  log "Setup complete"
  note "Backups, when needed, are stored under $BACKUP_DIR"
  note "Log out, choose Niri or Niri (DMS) on the login screen, then log back in."
}

main
