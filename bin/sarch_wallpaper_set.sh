#!/usr/bin/env bash
# Setzt ein Wallpaper mit awww und der eingestellten Transition
# (Einstellungen → Hintergrund → Übergang, gespeichert in ~/.config/sArch/wallpaper-transition.conf).
#   sarch_wallpaper_set.sh [bild]     ohne Bild: aktuelles Wallpaper erneut (zum Ausprobieren)
#
# Typen: random | grow | outer | wave | wipe | center | any | fade | slide | simple
#   random wählt bei jedem Wechsel einen anderen Effekt (mit zufälligem Winkel/Richtung)
img=${1:-$(head -n1 "$HOME/.cache/sArch/current_wallpaper" 2>/dev/null)}
[[ -f "$img" ]] || { echo "Wallpaper nicht gefunden: $img" >&2; exit 1; }

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

if [[ "$TYPE" == random ]]; then
    pool=(grow outer wave wipe center any fade slide)
    TYPE=${pool[RANDOM % ${#pool[@]}]}
fi
args=()
case "$TYPE" in
    slide)  dirs=(left right top bottom); args+=(--transition-type "${dirs[RANDOM % 4]}") ;;
    wave)   args+=(--transition-type wave --transition-angle $((RANDOM % 360)) --transition-wave "$((15 + RANDOM % 25)),$((15 + RANDOM % 25))") ;;
    wipe)   args+=(--transition-type wipe --transition-angle $((RANDOM % 360))) ;;
    grow|outer|center|any|fade|simple) args+=(--transition-type "$TYPE") ;;
    *)      args+=(--transition-type grow) ; TYPE=grow ;;
esac

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
# grow/outer: Kreis öffnet/schließt sich am Mauszeiger (center = Mitte, any = zufällige Stelle)
if [[ "$CURSOR" == true && -n "$pos" && "$TYPE" =~ ^(grow|outer)$ ]]; then
    args+=(--transition-pos "$pos")
fi
[[ "$FPS" == auto ]] && FPS=${hz:-60}
(( FPS > 240 )) && FPS=240

exec awww img "$img" "${args[@]}" \
    --transition-duration "$DURATION" \
    --transition-fps "$FPS" \
    --transition-bezier "$BEZIER"
