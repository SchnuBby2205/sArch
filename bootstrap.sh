#!/usr/bin/env bash
# sArch Bootstrap – für das Arch-Live-ISO
# Start:  curl -sL https://raw.githubusercontent.com/SchnuBby2205/sArch/main/bootstrap.sh | bash
# Mit Argument (z.B. Funktionsname für install.sh):
#         curl -sL <url> | bash -s -- <argument>
set -euo pipefail

REPO_URL="https://github.com/SchnuBby2205/sArch.git"
TARGET_DIR="${SARCH_DIR:-$HOME/sArch}"

# pacman braucht root (auf dem Live-ISO ist man root)
if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

echo ":: Installiere git ..."
$SUDO pacman -Sy --noconfirm git

echo ":: Hole sArch nach $TARGET_DIR ..."
if [[ -d "$TARGET_DIR/.git" ]]; then
    git -C "$TARGET_DIR" pull --ff-only
elif [[ -e "$TARGET_DIR" ]]; then
    echo "FEHLER: $TARGET_DIR existiert, ist aber kein Git-Repo. Abbruch." >&2
    exit 1
else
    git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
chmod +x install.sh

echo ":: Starte install.sh ..."
# Bei 'curl | bash' ist stdin die Pipe -> interaktive Menüs (read) würden nicht
# funktionieren. Daher stdin explizit vom Terminal holen.
exec ./install.sh "$@" </dev/tty
