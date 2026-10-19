#!/usr/bin/env bash
# Öffnet die sArch-Einstellungen (Quickshell). Optional: Seite (Kategorie oder INI-Sektion)
#   sarch_settings.sh             -> zuletzt geöffnete / erste Seite
#   sarch_settings.sh wallpaper   -> Hintergrundbild-Auswahl
#   sarch_settings.sh Keybindings
# Läuft der Quickshell-Daemon noch nicht, wird er gestartet.
page="${1:-}"
cfg="sarch"

if qs -c "$cfg" ipc call settings toggle "$page" &>/dev/null; then
    exit 0
fi

qs -c "$cfg" -n -d &>/dev/null
for _ in $(seq 1 40); do
    sleep 0.1
    qs -c "$cfg" ipc call settings open "$page" &>/dev/null && exit 0
done

# Fallback: alte GTK-Maske
exec python3 "$HOME/.config/sArch/bin/Settings/settings_mask.py" \
    "$HOME/.config/sArch/bin/Settings/settings_de.ini" --lang de ${page:+--page "$page"}
