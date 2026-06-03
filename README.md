```
 ███████╗ █████╗ ██████╗  ██████╗██╗  ██╗
 ██╔════╝██╔══██╗██╔══██╗██╔════╝██║  ██║
 ███████╗███████║██████╔╝██║     ███████║
 ╚════██║██╔══██║██╔══██╗██║     ██╔══██║
 ███████║██║  ██║██║  ██║╚██████╗██║  ██║
 ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
```

**My personal Arch Linux distribution — dotfiles, themes & install script**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org/)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![CSS](https://img.shields.io/badge/Theming-CSS%2FMatugen-1572B6?logo=css3&logoColor=white)](https://github.com/SchnuBby2205/sArch/tree/main/themes/Matugen)

---

## 🗂️ Overview

**sArch** is a personal Arch Linux setup containing everything needed to go from a fresh install to a fully configured, themed desktop environment — in a single command. It bundles shell scripts, config files, custom fonts, and a Matugen-based theming system.

---

## 📁 Repository Structure

```
sArch/
├── bin/                    # Custom executables & helper binaries
├── configs/
│   └── installConfigs/     # Install settings & constants
├── fonts/                  # Custom fonts used in the setup
├── scripts/
│   ├── io.sh               # I/O helper functions
│   ├── checks.sh           # Pre-install system checks
│   ├── commands.sh         # General command utilities
│   └── installs.sh         # Package & config installation logic
├── themes/
│   └── Matugen/            # Dynamic color theming via Matugen
├── install.sh              # 🚀 Main entry point
└── LICENSE
```

---

## 🚀 Installation

> **Prerequisites:** A working Arch Linux base install with `sudo` access.

```bash
# 1. Clone the repository
git clone https://github.com/SchnuBby2205/sArch.git
cd sArch

# 2. Make the install script executable
chmod +x install.sh

# 3. Run the installer
./install.sh
```

---

## 🎨 Theming

sArch uses **[Matugen](https://github.com/InioX/matugen)** for dynamic, material-you-inspired color theming. Theme files are located in `themes/Matugen/` and are applied as part of the install process.

---

## 🧩 Components

| Component | Description |
|-----------|-------------|
| `scripts/io.sh` | Logging & user I/O helpers |
| `scripts/checks.sh` | Validates system requirements before install |
| `scripts/commands.sh` | Reusable command wrappers |
| `scripts/installs.sh` | Core installation routines |
| `configs/installConfigs/` | User-facing configuration & constants |
| `fonts/` | Custom fonts bundled with the setup |
| `themes/Matugen/` | Matugen color scheme definitions |

---

## ⚠️ Disclaimer

This is a **personal configuration**. It is tailored to my own hardware and preferences. Feel free to fork and adapt it, but be aware that things may not work out of the box on your system without adjustments.

---

## 📄 License

Distributed under the [MIT License](LICENSE).

---

Made with ❤️ and Arch Linux by [SchnuBby2205](https://github.com/SchnuBby2205)
