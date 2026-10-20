#!/usr/bin/env bash
# Startet die sArch-Quickshell (Bar, Einstellungen, Benachrichtigungen), sofern sie nicht deaktiviert ist.
# An/aus: install.sh -> Install -> Quickshell  (Schalter: ~/.config/sArch/quickshell.disabled)
# Ohne Quickshell übernimmt Dunst die Benachrichtigungen (startet automatisch per D-Bus).
[[ -e "$HOME/.config/sArch/quickshell.disabled" ]] && exit 0
qs_bin=$(command -v qs || command -v quickshell) || exit 0
# Quickshell stellt den Benachrichtigungsdienst -> laufenden Dunst beenden, sonst bleibt der Name belegt
pkill -x dunst 2>/dev/null && sleep 0.3
exec "$qs_bin" -c sarch -n -d
