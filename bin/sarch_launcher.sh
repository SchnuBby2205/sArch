#!/usr/bin/env bash
# Öffnet den App-Launcher: Quickshell (wenn aktiv), sonst Rofi.
# Läuft noch eine ältere Quickshell-Instanz ohne Launcher, wird sie einmal neu gestartet.
log="$HOME/.cache/sArch/launcher.log"
mkdir -p "${log%/*}"

if [[ ! -e "$HOME/.config/sArch/quickshell.disabled" ]] && command -v qs >/dev/null; then
    qs -c sarch ipc call launcher toggle &>>"$log" && exit 0
    if qs -c sarch ipc show &>/dev/null; then
        # Instanz läuft, kennt aber "launcher" nicht -> neu starten
        echo "$(date '+%F %T') launcher-Target fehlt, starte Quickshell neu" >> "$log"
        qs kill -c sarch &>/dev/null || pkill -f '(^|/)[q](s|uickshell) .*-c sarch( |$)'
        sleep 0.5
    fi
    qs -c sarch -n -d &>>"$log"
    for _ in $(seq 1 30); do
        sleep 0.15
        qs -c sarch ipc call launcher open &>>"$log" && exit 0
    done
    echo "$(date '+%F %T') Quickshell-Launcher nicht erreichbar -> Rofi" >> "$log"
fi
exec rofi -show drun -theme "$HOME/.config/rofi/launcher.rasi"
