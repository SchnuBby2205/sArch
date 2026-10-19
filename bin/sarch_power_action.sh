#!/usr/bin/env bash
# Führt eine Power-Aktion aus (vom Quickshell-Powermenü aufgerufen).
#   sarch_power_action.sh lock|suspend|hibernate|logout|reboot|shutdown
case "${1:-}" in
    lock)
        if command -v hyprlock >/dev/null; then pidof hyprlock >/dev/null || exec hyprlock
        elif command -v betterlockscreen >/dev/null; then exec betterlockscreen -l
        else exec loginctl lock-session
        fi ;;
    suspend)
        command -v playerctl >/dev/null && playerctl -a pause 2>/dev/null
        exec systemctl suspend ;;
    hibernate)
        exec systemctl hibernate ;;
    logout)
        # Hyprland >= 0.56 (Lua): hl.dsp.exit(), sonst klassisch, zuletzt die Sitzung beenden
        out=$(hyprctl dispatch 'hl.dsp.exit()' 2>&1)
        [[ "${out,,}" == ok* ]] && exit 0
        out=$(hyprctl dispatch exit 2>&1)
        [[ "${out,,}" == ok* ]] && exit 0
        exec loginctl terminate-session "${XDG_SESSION_ID:-self}" ;;
    reboot)
        exec systemctl reboot ;;
    shutdown)
        exec systemctl poweroff ;;
    *)
        echo "usage: $0 lock|suspend|hibernate|logout|reboot|shutdown" >&2; exit 2 ;;
esac
