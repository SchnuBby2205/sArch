#!/usr/bin/env bash
# Setzt ein Wallpaper mit der eingestellten Transition
# (Einstellungen → Hintergrund → Übergang, gespeichert in ~/.config/sArch/wallpaper-transition.conf).
#   sarch_wallpaper_set.sh <bild>     neues Wallpaper
#   sarch_wallpaper_set.sh --try      Vorschau: aktuelles Bild -> abgedunkelte Version -> zurück
#
# Typen: random | grow | outer | wave | wipe | center | any | fade | slide | slice | flip | simple
#   awww-Effekte laufen direkt über awww; slice (Zerschneiden) und flip (Kacheln) zeichnet Quickshell.
#   random wählt einen Effekt (mit zufälligem Winkel/Richtung). SARCH_WP_TYPE überschreibt den Typ.
state="$HOME/.cache/sArch/current_wallpaper"
current=$(head -n1 "$state" 2>/dev/null)

# Standardwerte
TYPE=random
DURATION=1.6
BEZIER=".54,0,.34,.99"
CURSOR=true        # grow/outer starten am Mauszeiger
FPS=auto           # auto = Bildwiederholrate des Monitors

conf="$HOME/.config/sArch/wallpaper-transition.conf"
if [[ -f "$conf" ]]; then
    while IFS='=' read -r k v; do
        v=${v//[^a-zA-Z0-9.,_-]/}                       # nur harmlose Zeichen übernehmen
        case "$k" in
            TYPE) TYPE=$v ;; DURATION) DURATION=$v ;; BEZIER) BEZIER=$v ;; CURSOR) CURSOR=$v ;; FPS) FPS=$v ;;
        esac
    done < "$conf"
fi
TYPE=${SARCH_WP_TYPE:-$TYPE}
qs_bin=$(command -v qs || command -v quickshell)

if [[ "$TYPE" == random ]]; then
    pool=(grow outer wave wipe center any fade slide)
    [[ -n "$qs_bin" ]] && pool+=(slice flip slice flip)          # eigene Effekte etwas häufiger
    TYPE=${pool[RANDOM % ${#pool[@]}]}
fi

# Mauszeiger (in % des Monitors, y von unten) und Bildwiederholrate aus Hyprland
read -r pos hz < <(python3 - <<'PY' 2>/dev/null
import json, subprocess
def j(*a):
    return json.loads(subprocess.run(["hyprctl", "-j", *a], capture_output=True, text=True, timeout=2).stdout)
try:
    c, mons = j("cursorpos"), j("monitors")
    for m in mons:
        s = m.get("scale") or 1
        w, h = m["width"] / s, m["height"] / s
        if m["x"] <= c["x"] < m["x"] + w and m["y"] <= c["y"] < m["y"] + h:
            print(f'{(c["x"] - m["x"]) / w:.3f},{1 - (c["y"] - m["y"]) / h:.3f} {round(m.get("refreshRate") or 60)}')
            break
except Exception:
    pass
PY
)
[[ "$FPS" == auto ]] && FPS=${hz:-60}
(( FPS > 240 )) && FPS=240

# awww-Argumente für den gewählten Typ (einmal auswürfeln, für --try beide Richtungen gleich)
args=()
case "$TYPE" in
    slide)  dirs=(left right top bottom); args+=(--transition-type "${dirs[RANDOM % 4]}") ;;
    wave)   args+=(--transition-type wave --transition-angle $((RANDOM % 360)) --transition-wave "$((15 + RANDOM % 25)),$((15 + RANDOM % 25))") ;;
    wipe)   args+=(--transition-type wipe --transition-angle $((RANDOM % 360))) ;;
    grow|outer|center|any|fade|simple|slice|flip) args+=(--transition-type "$TYPE") ;;
    *)      TYPE=grow; args+=(--transition-type grow) ;;
esac
# grow/outer: Kreis öffnet/schließt sich am Mauszeiger (center = Mitte, any = zufällige Stelle)
if [[ "$CURSOR" == true && -n "$pos" && "$TYPE" =~ ^(grow|outer)$ ]]; then
    args+=(--transition-pos "$pos")
fi

# set <alt> <neu>
set_wp() {
    local old=$1 new=$2
    if [[ "$TYPE" == slice || "$TYPE" == flip ]]; then
        # eigener Effekt in Quickshell; ohne Quickshell (oder ohne altes Bild) -> Wischen
        if [[ -n "$qs_bin" && -f "$old" ]] \
            && "$qs_bin" -c sarch ipc call wallpaper transition "$old" "$new" "$TYPE" "$DURATION" &>/dev/null; then
            return 0
        fi
        awww img "$new" --transition-type wipe --transition-angle 32 \
            --transition-duration "$DURATION" --transition-fps "$FPS" --transition-bezier "$BEZIER"
        return
    fi
    awww img "$new" "${args[@]}" \
        --transition-duration "$DURATION" \
        --transition-fps "$FPS" \
        --transition-bezier "$BEZIER"
}

if [[ "${1:-}" == --try ]]; then
    [[ -f "$current" ]] || { echo "Kein aktuelles Wallpaper" >&2; exit 1; }
    tmp="$HOME/.cache/sArch/wallpaper_try.jpg"
    magick "$current" -resize 1920x1080^ -blur 0x22 -modulate 55,80 "$tmp" 2>/dev/null || exit 1
    set_wp "$current" "$tmp"
    sleep "$(awk -v d="$DURATION" 'BEGIN { print d + 0.7 }')"
    set_wp "$tmp" "$current"
    exit 0
fi

img=${1:-$current}
[[ -f "$img" ]] || { echo "Wallpaper nicht gefunden: $img" >&2; exit 1; }
set_wp "$current" "$img"
