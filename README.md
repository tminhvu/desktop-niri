# Niri desktop setup

This repository reproduces the two Niri sessions used on the source machine:

- **Niri** — Waybar, Swaybg, Fuzzel, Xfce Terminal, lxpolkit, and IBus Bamboo.
- **Niri (DMS)** — DankMaterialShell with the same Niri bindings, blue color family, wallpaper, input method, and compact bottom bar.

The automated package bootstrap targets **Ubuntu 26.04 or newer**. The configuration layer can be installed on another distribution after its equivalent packages are installed.

## Install on a new machine

```sh
git clone <repository-url> ~/niri-desktop
cd ~/niri-desktop
./setup.sh
```

The script requests `sudo` only for package installation and system integration. It backs up conflicting files under:

```text
~/.local/state/niri-dotfiles-backups/<timestamp>/
```

After setup completes, log out. The login screen will offer both **Niri** and **Niri (DMS)**.

Useful modes:

```sh
./setup.sh --dry-run
./setup.sh --skip-packages
```

Use `--skip-packages` on a non-Ubuntu distribution after installing equivalent packages yourself.

## What setup installs

The Ubuntu bootstrap installs:

- Niri and its Wayland session support
- DankMaterialShell and Matugen
- Waybar and Fuzzel
- Xfce Terminal
- Swaybg and Swaylock
- PipeWire/WirePlumber controls, Pavucontrol, brightness and power-profile tools
- IBus with Bamboo Vietnamese input
- keyd
- Noto, Font Awesome, and Iosevka Nerd Font Mono
- XDG portals and Xwayland Satellite

The script then deploys:

- shared Niri bindings, layout, input, and display configuration;
- the normal Waybar session and separate DMS session;
- centered Waybar clock and working audio glyphs;
- the blue `#7fc8ff` Fuzzel and DMS color family;
- the shared `wall-2.png` wallpaper;
- the compact DMS bar with 16 px active and 12 px inactive workspace pills;
- the Xfce Terminal navy palette, Iosevka font, compact tabs, and 120×30 default size;
- IBus Bamboo/Telex with `Alt+Z` switching;
- Caps Lock/Escape swapping through keyd, except for the SDINNO keyboard (`36ae:fe9c`).

## Hardware-specific settings

The source display is configured in `niri/base.kdl` as:

```kdl
output "HDMI-A-1" {
    mode "1920x1080@99.998"
    scale 1
}
```

Niri safely ignores an output block when that connector is absent, but a different monitor will use its own default mode. Run `niri msg outputs` and update the block if the new machine uses another connector or refresh rate.

The keyd exclusion is tied to the SDINNO USB identifier. Use `sudo keyd monitor` if the excluded keyboard has a different identifier on another machine.

## Configuration ownership

These directories are symlinked directly to the clone:

- `~/.config/niri`
- `~/.config/waybar`
- `~/.config/fuzzel`
- `~/.config/matugen`

DMS, GTK, Xfce Terminal, IBus, keyd, session files, and the wallpaper are installed as generated or copied files because those applications may rewrite their state.

Fuzzel's generated Material palette lives at `~/.cache/niri-desktop/fuzzel-colors.ini`, so changing a DMS palette does not dirty the Git checkout or collide with Fuzzel's own cache file.

## Maintenance

Rerunning `./setup.sh` is safe and refreshes managed files. A DMS package upgrade can replace the compact workspace-pill modification; rerun setup to reapply it.

The installer validates both Niri sessions, the Fuzzel configuration, JSON theme files, and its own shell syntax before reporting success.
