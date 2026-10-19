#!/usr/bin/env bash
# Startet die sArch-Quickshell (Bar + Einstellungen), sofern sie nicht deaktiviert ist.
# An/aus: install.sh -> Install -> Quickshell  (Schalter: ~/.config/sArch/quickshell.disabled)
[[ -e "$HOME/.config/sArch/quickshell.disabled" ]] && exit 0
qs_bin=$(command -v qs || command -v quickshell) || exit 0
exec "$qs_bin" -c sarch -n -d
