#!/usr/bin/env bash
# sArch Bootstrap – für das Arch-Live-ISO
# Start:  curl -sL https://raw.githubusercontent.com/SchnuBby2205/sArch/main/bootstrap.sh | bash
# Mit Argument (z.B. Funktionsname für install.sh):
#         curl -sL <url> | bash -s -- <argument>
# Anderer Branch (z.B. zum Testen):
#         curl -sL https://raw.githubusercontent.com/SchnuBby2205/sArch/<branch>/bootstrap.sh | SARCH_BRANCH=<branch> bash
set -euo pipefail

REPO_URL="https://github.com/SchnuBby2205/sArch.git"
TARGET_DIR="${SARCH_DIR:-$HOME/sArch}"
BRANCH="${SARCH_BRANCH:-main}"

# pacman braucht root (auf dem Live-ISO ist man root)
if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

echo ":: Installiere git und terminus-font ..."
# terminus-font: Konsolenschrift für den Installer-Screen (auf dem ISO meist schon vorhanden)
$SUDO pacman -Sy --noconfirm --needed git terminus-font

echo ":: Hole sArch ($BRANCH) nach $TARGET_DIR ..."
if [[ -d "$TARGET_DIR/.git" ]]; then
    git -C "$TARGET_DIR" fetch origin "$BRANCH"
    git -C "$TARGET_DIR" checkout "$BRANCH" 2>/dev/null \
        || git -C "$TARGET_DIR" checkout -b "$BRANCH" "origin/$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
elif [[ -e "$TARGET_DIR" ]]; then
    echo "FEHLER: $TARGET_DIR existiert, ist aber kein Git-Repo. Abbruch." >&2
    exit 1
else
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
chmod +x install.sh

echo ":: Starte install.sh ..."
# Bei 'curl | bash' ist stdin die Pipe -> interaktive Menüs (read) würden nicht
# funktionieren. Daher stdin explizit vom Terminal holen.
exec ./install.sh "$@" </dev/tty
