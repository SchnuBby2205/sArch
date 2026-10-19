#!/usr/bin/env bash
# Öffnet das Powermenü: Quickshell (wenn aktiv), sonst das alte Rofi-Menü.
# Läuft noch eine ältere Quickshell-Instanz ohne Powermenü, wird sie einmal neu gestartet.
log="$HOME/.cache/sArch/power.log"
mkdir -p "${log%/*}"

if [[ ! -e "$HOME/.config/sArch/quickshell.disabled" ]] && command -v qs >/dev/null; then
    qs -c sarch ipc call power toggle &>>"$log" && exit 0
    if qs -c sarch ipc show &>/dev/null; then
        # Instanz läuft, kennt aber "power" nicht -> neu starten
        echo "$(date '+%F %T') power-Target fehlt, starte Quickshell neu" >> "$log"
        qs kill -c sarch &>/dev/null || pkill -f '(^|/)[q](s|uickshell) .*-c sarch( |$)'
        sleep 0.5
    fi
    qs -c sarch -n -d &>>"$log"
    for _ in $(seq 1 30); do
        sleep 0.15
        qs -c sarch ipc call power open &>>"$log" && exit 0
    done
    echo "$(date '+%F %T') Quickshell-Powermenü nicht erreichbar -> Rofi" >> "$log"
fi
exec "$HOME/.config/sArch/bin/sarch_powermenu.sh"
