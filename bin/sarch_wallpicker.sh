#!/usr/bin/env bash
# Wallpaper-Picker (SUPER+W): Filmstreifen von Quickshell; Auswahl schließt ihn sofort,
# damit der Übergang sichtbar ist. Ohne Quickshell -> Einstellungsseite (GTK-Maske).
log="$HOME/.cache/sArch/launcher.log"
mkdir -p "${log%/*}"

if [[ ! -e "$HOME/.config/sArch/quickshell.disabled" ]] && command -v qs >/dev/null; then
    qs -c sarch ipc call wallpicker toggle &>>"$log" && exit 0
    if qs -c sarch ipc show &>/dev/null; then
        # Instanz läuft, kennt "wallpicker" aber noch nicht (altes Shell-Update) -> neu starten
        echo "$(date '+%F %T') wallpicker-Target fehlt, starte Quickshell neu" >> "$log"
        qs kill -c sarch &>/dev/null || pkill -f '(^|/)[q](s|uickshell) .*-c sarch( |$)'
        sleep 0.5
    fi
    qs -c sarch -n -d &>>"$log"
    for _ in $(seq 1 30); do
        sleep 0.15
        qs -c sarch ipc call wallpicker open &>>"$log" && exit 0
    done
fi
exec "$HOME/.config/sArch/bin/sarch_settings.sh" wallpaper
