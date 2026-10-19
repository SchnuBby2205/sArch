#!/usr/bin/env bash
# Öffnet den App-Launcher: Quickshell (wenn aktiv), sonst Rofi.
if [[ ! -e "$HOME/.config/sArch/quickshell.disabled" ]] && command -v qs >/dev/null \
   && qs -c sarch ipc call launcher toggle &>/dev/null; then
    exit 0
fi
exec rofi -show drun -theme "$HOME/.config/rofi/launcher.rasi"
