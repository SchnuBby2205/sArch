#!/bin/bash
# sArch-ISO lokal bauen – in einem Arch-Container (Docker oder Podman), das Host-System bleibt sauber.
#   ./iso/build_local.sh                     -> iso/out/sarch-*.iso
#   SARCH_KERNEL=linux ./iso/build_local.sh  (Standard: linux-lts)
# Voraussetzung (Arch):  sudo pacman -S docker && sudo systemctl start docker
#                  oder: sudo pacman -S podman
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if command -v podman >/dev/null; then RT=podman; elif command -v docker >/dev/null; then RT=docker
else echo "Docker oder Podman wird benötigt (sudo pacman -S docker)" >&2; exit 1; fi
SUDO=""; [[ $EUID -ne 0 ]] && SUDO=sudo
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
echo "==> Baue sArch-ISO mit $RT (Branch $BRANCH) – dauert je nach Rechner 20-60 Minuten"
$SUDO $RT run --rm --privileged \
    -v "$REPO:/src" -w /src \
    -e SARCH_KERNEL="${SARCH_KERNEL:-linux-lts}" -e SARCH_BRANCH="$BRANCH" -e SARCH_KEEP_WORK="${SARCH_KEEP_WORK:-0}" -e SARCH_ZSTD_LEVEL="${SARCH_ZSTD_LEVEL:-6}" \
    docker.io/archlinux/archlinux:latest \
    bash iso/build_iso.sh
# Container läuft als root -> Ergebnis dem Benutzer zurückgeben
[[ -n "$SUDO" ]] && $SUDO chown -R "$(id -u):$(id -g)" "$REPO/iso/out" "$REPO/iso/work" "$REPO/iso/aurcache" 2>/dev/null
ls -lh "$REPO/iso/out"
