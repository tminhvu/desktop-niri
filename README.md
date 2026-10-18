# Niri desktop setup

This repository reproduces the two Niri sessions used on the source machine:

- **Niri** — Waybar, Swaybg, Fuzzel, Xfce Terminal, lxpolkit, and Fcitx 5 Bamboo.
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
- Fcitx 5 with Bamboo Vietnamese input and GTK/Qt frontends
- Python evdev for the SDINNO keyboard chatter filter
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
- Fcitx 5 Bamboo/Telex with `Alt+Z` switching;
- native Wayland input for GTK 3/4, Fcitx modules for GTK on XWayland, a Wayland-first Qt 6 fallback, and Fcitx compatibility for Qt 5, SDL, and XWayland;
- Caps Lock and Escape both send Escape through Niri's `caps:escape` option;
- a 40 ms per-key chatter filter for the SDINNO keyboard (`36ae:fe9c`), started automatically at boot.

## Remember a window's opening mode

- `Super+S`: toggle floating for the current window.
- `Super+Shift+Alt+S`: remember floating for a specific window title.
- `Super+F`: toggle the current column's maximized width.
- `Super+Shift+Alt+F`: remember full-width tiling for a specific window title (bar stays visible).

Focus the popup or dialog, press the remember shortcut, and choose its exact title or a title pattern. Patterns accept `*` for any text and `?` for one character; other characters are literal. Every rule also requires the exact app ID, so a Chrome extension popup can be targeted without changing ordinary Chrome windows. Review the app ID, pattern and current match count, then select **Save preference**. Matching saved rules can be removed from the same picker. Escape cancels without saving.

The watcher catches titles that appear after a window opens. Each preference is applied once per window; subsequent manual changes are respected. Remembered maximization sets the column to 100% width by window ID, keeping focus and the bar intact. This has the same full-width appearance as `Super+F`, but does not toggle Niri's internal maximized flag. Choosing a different mode for the same pattern replaces its previous mode; later overlapping rules take precedence. Removing a rule leaves existing windows as they are.

Rules persist in `~/.config/niri-window-memory/rules.json`, shared by normal Niri and DMS. Setup preserves this folder. Copy it to another machine to transfer your saved preferences. The helper starts automatically in both sessions and uses only Python's standard library, Fuzzel and Niri IPC. Windows with identical app IDs and titles cannot be distinguished, and embedded browser popups that Niri does not expose as separate windows cannot be targeted.

## Hardware-specific settings

The source display is configured in `niri/base.kdl` as:

```kdl
output "HDMI-A-1" {
    mode "1920x1080@99.998"
    scale 1
}
```

Niri safely ignores an output block when that connector is absent, but a different monitor will use its own default mode. Run `niri msg outputs` and update the block if the new machine uses another connector or refresh rate.

The chatter filter targets USB device `36ae:fe9c` and waits when it is disconnected. It grabs that device and emits filtered input through a virtual keyboard. Repeated presses within 40 ms of release are suppressed; intentional taps within that window are suppressed too. Other keyboards are unaffected. To change the target or threshold, edit `system/chatter-filter/chatter-filter.service` and rerun setup. List devices with `sudo /usr/local/bin/chatter-filter-linux.py --list`; inspect activity with `journalctl -u chatter-filter.service`.

Setup retires the exact old keyd swap rule installed by this repo, preserving it as a timestamped backup. Unrelated keyd configurations are preserved.

## Configuration ownership

These directories are symlinked directly to the clone:

- `~/.config/niri`
- `~/.config/waybar`
- `~/.config/fuzzel`
- `~/.config/matugen`

DMS, GTK, Xfce Terminal, Fcitx 5, the chatter filter, session files, and the wallpaper are installed as generated or copied files.

Fuzzel's generated Material palette lives at `~/.cache/niri-desktop/fuzzel-colors.ini`, so changing a DMS palette does not dirty the Git checkout or collide with Fuzzel's own cache file.

## Maintenance

Rerunning `./setup.sh` is safe and refreshes managed files. A DMS package upgrade can replace the compact workspace-pill modification; rerun setup to reapply it.

The installer validates both Niri sessions, the Fuzzel configuration, JSON theme files, and its own shell syntax before reporting success.
