```
 ███████╗ █████╗ ██████╗  ██████╗██╗  ██╗
 ██╔════╝██╔══██╗██╔══██╗██╔════╝██║  ██║
 ███████╗███████║██████╔╝██║     ███████║
 ╚════██║██╔══██║██╔══██╗██║     ██╔══██║
 ███████║██║  ██║██║  ██║╚██████╗██║  ██║
 ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
```

**My personal Arch Linux distribution — dotfiles, themes & install script**

🇬🇧 English · [🇩🇪 Deutsch](README.de.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org/)
[![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?logo=hyprland&logoColor=black)](https://hyprland.org/)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Theming](https://img.shields.io/badge/Theming-Matugen-1572B6)](https://github.com/InioX/matugen)

---

## 🗂️ Overview

**sArch** takes a machine from the Arch Linux live ISO to a fully configured, themed **Hyprland** desktop with a single command. It bundles the install script, all dotfiles, fonts, a GTK theme and a [Matugen](https://github.com/InioX/matugen)-based color system that follows the current wallpaper.

The installer screen is styled after [Omarchy](https://github.com/basecamp/omarchy): the logo sits in the middle, each stage shows a progress bar underneath, and the latest lines of the install log scroll by dimmed below it.

![Installer preview](docs/installer-preview.png)

---

## 🚀 Installation

> **Prerequisites:** the Arch Linux live ISO booted in **UEFI mode**, a working internet connection and partitions for **boot (EFI)**, **swap** and **root**. The installer can open `cfdisk` for you if they don't exist yet.

```bash
curl -fsSL https://raw.githubusercontent.com/SchnuBby2205/sArch/main/bootstrap.sh | bash
```

Install a different branch (e.g. for testing):

```bash
curl -fsSL https://raw.githubusercontent.com/SchnuBby2205/sArch/sArch-QS/bootstrap.sh | SARCH_BRANCH=sArch-QS bash
```

`bootstrap.sh` installs `git` and `terminus-font`, clones the repo to `~/sArch` (or `$SARCH_DIR`, branch via `$SARCH_BRANCH`, default `main`) and starts `install.sh` with the main menu:

- **Settings** – review or change every install setting (partitions, hostname, user, CPU, GPU, timezone, locale, keymap, kernel, backup/games drives). Values are saved to `configs/installConfigs/install_settings`.
- **Install** – start a stage manually (normally you only start *Base System*, the rest continues on its own).
- **Exit**

### Live ISO with graphical installer (Calamares)

There is also a bootable ISO: it boots straight into the sArch desktop and installs with **Calamares** (offline, incl. partitioning/LUKS, users, GRUB). Ready-made ISOs are on the **[Releases](https://github.com/SchnuBby2205/sArch/releases/latest)** page (split into parts; join with `cat sarch-*.iso.part* > sarch.iso` on Linux or `copy /b part1 + part2 sarch.iso` on Windows). Build it yourself with **GitHub Actions** (tag `iso-…` = test build, `release-…` = release) or locally with `./iso/build_local.sh`. On first boot a setup step offers NVIDIA drivers, extra programs and backups. Details (German): [iso/README.md](iso/README.md).

### Install stages

| # | Stage | Runs | What happens |
|---|-------|------|--------------|
| 1 | **Base System** | live ISO | Asks for missing settings, formats and mounts the partitions (after typing `YES`), sets up mirrors with `reflector`, runs `pacstrap` |
| 2 | **Arch-Chroot** | automatically inside `arch-chroot` | Timezone, locale, keymap, console font, GRUB, hostname, user, temporary install mode (passwordless sudo + tty1 autologin), NetworkManager; then reboot |
| 3 | **Desktop** | automatic login on **tty1** | Enables multilib, installs system, audio and program packages plus `yay`, links configs, installs fonts, GTK theme and wallpapers, enables SDDM; then reboot |
| 4 | **Configs** | first Hyprland start (SDDM autologin, fullscreen kitty) | GPU drivers (AMD/NVIDIA), `dxvk-bin`, Firefox profile (created without opening Firefox), optionally backups / personal specifics, first wallpaper + Matugen colors, **root and user passwords**, install mode removed; then reboot |

Every stage hands over to the next one by itself (chroot call, `.bashrc` hook on tty1, Hyprland autostart). The hooks are removed again once they've done their job.

### Options

The following switches live in `configs/installConfigs/install_settings`:

| Setting | Effect |
|---------|--------|
| `debug=true` | Shows command output live instead of the installer screen |
| `dryRun=true` | Only logs the commands; the progress bar still moves, so you can preview the whole flow |
| `defaults=true` | Skips the backup/specifics question in the last stage |

Everything is logged to `~/sArch-install.log`. If a command fails, the stage title turns red and the end of the log is shown.

**Preview the installer screen** without installing anything:

```bash
./install.sh presentationDemo
```

---

## 🖥️ Installer screen

| File / setting | Purpose |
|----------------|---------|
| `logo.txt` | The centered logo – replace it with any ASCII art you like |
| `scripts/presentation.sh` | Layout, progress bar, spinner and live log tail |
| `consoleFont` in `configs/installConfigs/constants` | TTY font (default `ter-v22b`, empty = don't change). It is also written to `/etc/vconsole.conf` |

The layout is recalculated for every screen, so it works on the TTY as well as in kitty. On the Linux console, characters the font doesn't have are replaced by ASCII equivalents.

---

## 🎨 Theming

- **[Matugen](https://github.com/InioX/matugen)** generates the color scheme from the current wallpaper and fills the templates in `configs/matugen/templates/` (Hyprland, kitty, rofi, dunst, btop, yazi, GTK, Qt and Firefox via pywalfox).
- **`themes/Matugen/`** is the GTK 3/4 theme that picks up those colors; it is installed to `~/.themes`.
- Wallpapers are cloned to `~/Bilder/Wallpapers`. The **Settings app** (page *Hintergrund*, `SUPER + W`) switches the wallpaper and re-runs Matugen with the chosen accent color.
- **Language:** the Quickshell UI (settings, bar, launcher, notifications, power menu) follows the system language (`LANG`): German for `de_*`, English otherwise. Force it with `SARCH_SETTINGS_LANG=en` (or `de`), e.g. `hl.env("SARCH_SETTINGS_LANG", "en")` in `configs/hypr/env.lua`. Translations live in `configs/quickshell/sarch/i18n/<lang>.json` (German source text → translation).

---

## 📁 Repository structure

```
sArch/
├── bootstrap.sh            # Entry point for the live ISO (curl | bash)
├── install.sh              # Main menu & stage dispatcher
├── logo.txt                # Logo for the installer screen
├── scripts/
│   ├── io.sh               # Output, prompts, menus (list), settings menu
│   ├── presentation.sh     # Omarchy-style installer screen
│   ├── checks.sh           # UEFI/partition checks, settings prompts
│   ├── commands.sh         # runCMDS, dryRun, safeCMD
│   └── installs.sh         # The four install stages, backups, specifics
├── configs/
│   ├── installConfigs/     # Settings, constants, package & choice lists
│   ├── hypr/               # Hyprland (Lua config)
│   ├── kitty/ rofi/ dunst/ nvim/ yazi/ btop/ qt5ct/ qt6ct/ neru/
│   └── matugen/            # Matugen config & templates
├── bin/                    # sarch_* helper scripts + Settings tool
├── fonts/                  # Bundled fonts
├── themes/Matugen/         # GTK theme
└── docs/                   # Screenshots
```

Configs and `bin/` are **symlinked** into `~/.config` and `~/.config/sArch/bin`, so changes in the repo take effect immediately.

### Package lists

The files in `configs/installConfigs/` (`systemdeps`, `audiodeps`, `programs`, `programs_extra`, `fonts`, `amd`, `nvidia`) share a simple format:

```
Display name...      # line 1: label on the progress screen
5                    # line 2: progress bar position after this list (out of 20)
package-a package-b  # remaining lines: packages (brace expansion works)
```

`cpus`, `gpus`, `kernels`, `timezones`, `locales` and `keymaps` provide the choices for the settings menu. An `Other` entry allows free text input.

---

## 🧰 Helper scripts (`bin/`)

| Script | Purpose |
|--------|---------|
| `Settings/settings_mask.py` | Settings app (GTK4/libadwaita, `SUPER + ALT + S`): Hyprland, wallpaper + accent color (`SUPER + W` opens it via `--page wallpaper`), fonts for Dunst/rofi/kitty, Dunst position. Pages are defined in `Settings/settings_de.ini` |
| `sarch_change_volume.sh` / `sarch_volume.sh` | Volume control with notification / rofi menu |
| `sarch_powermenu.sh` | Power menu (rofi) |

---

## 💾 Backups & personal specifics

In the last stage you can choose to also:

- **Restore backups:** mount `BACKUP_DEV` at `BACKUP_MNT` and symlink Lutris, the zsh history, git config/credentials, TeamSpeak and the Firefox profile from `BACKUP_DIR`. Existing files are renamed to `*_bak_<timestamp>`; only the freshly created Firefox profile is replaced.
- **Install personal specifics:** add the backup and games drives to `fstab` (by UUID), set up SDDM autologin into Hyprland, set the GRUB timeout to 0.

Both are tailored to my own machine. Adjust the `BACKUP_*` / `GAMES_*` values in the settings first, or skip them.

---

## ⚠️ Disclaimer

This is a **personal configuration** tailored to my own hardware and preferences. Stage 1 **formats the selected partitions without further warning**, so double-check them. Feel free to fork and adapt it, and preferably try it in a VM first.

---

## 📄 License

Distributed under the [MIT License](LICENSE).

---

Made with ❤️ and Arch Linux by [SchnuBby2205](https://github.com/SchnuBby2205)
