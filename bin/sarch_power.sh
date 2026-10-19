#!/usr/bin/env bash
# Öffnet das Powermenü: Quickshell (wenn aktiv), sonst das alte Rofi-Menü.
if [[ ! -e "$HOME/.config/sArch/quickshell.disabled" ]] && command -v qs >/dev/null \
   && qs -c sarch ipc call power toggle &>/dev/null; then
    exit 0
fi
exec "$HOME/.config/sArch/bin/sarch_powermenu.sh"
