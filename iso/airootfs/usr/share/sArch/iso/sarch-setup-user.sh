#!/bin/bash
# sArch-Desktop für einen Benutzer einrichten – wie installDE, aber ohne Netz (alles liegt auf der ISO)
#   sarch-setup-user.sh <benutzer> [live|target]     (als root)
#   live:   Live-ISO; Wallpaper werden nur verlinkt
#   target: installiertes System (Calamares, chroot); Wallpaper werden verschoben,
#           beim ersten Hyprland-Start folgt die Ersteinrichtung (install.sh installISOFirstboot)
set -u
SRC=/opt/sArch
WP=/usr/share/sArch/wallpapers

# --- Teil, der als Benutzer läuft ---
if [[ "${1:-}" == --as-user ]]; then
    MODE=$2
    repo="$HOME/sArch"
    cd "$HOME" || exit 1
    mkdir -p .config/sArch .local/share .themes .cache/sArch Bilder
    for d in "$repo/configs/"*; do
        [[ "${d##*/}" == installConfigs ]] && continue
        ln -sfnT "$d" ".config/${d##*/}"
    done
    ln -sfnT "$repo/bin" .config/sArch/bin
    [[ -d .themes/Matugen ]] || cp -a "$repo/themes/Matugen" .themes/
    [[ -d .local/share/fonts ]] || cp -a "$repo/fonts" .local/share/fonts
    fc-cache -f >/dev/null 2>&1 || true
    sed -i "s|/home/schnubby/|$HOME/|g" "$repo/configs/matugen/templates/rofi-colors.rasi" "$repo/configs/rofi/colors.rasi" "$repo/configs/btop/btop.conf" 2>/dev/null

    # Theme: zufälliges Wallpaper + Matugen-Farben (ohne awww – der läuft hier noch nicht;
    # gesetzt wird das Bild beim ersten Start von bin/sarch_wallpaper_restore.sh)
    if [[ ! -s .cache/sArch/current_wallpaper ]]; then
        wp=$(find -L "$HOME/Bilder/Wallpapers/" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | shuf -n 1)
        if [[ -n "$wp" ]]; then
            mkdir -p .cache/Wallpaper_thumbs
            magick "$wp" -thumbnail 500x500^ -gravity center -extent 500x500 -quality 70 .cache/Wallpaper_thumbs/curr 2>/dev/null
            magick "$wp" -thumbnail 1000x500^ -gravity center -extent 1000x500 -quality 70 .cache/Wallpaper_thumbs/curr_wide 2>/dev/null
            cfg=$(mktemp --suffix=.toml)
            sed -E 's/^set[[:space:]]*=[[:space:]]*true/set = false/' "$repo/configs/matugen/config.toml" > "$cfg"
            timeout 90 matugen image "$wp" -c "$cfg" >/dev/null 2>&1 || true
            rm -f "$cfg"
            printf '%s\n0\n' "$wp" > .cache/sArch/current_wallpaper
        fi
    fi

    # Zielsystem: Ersteinrichtung (NVIDIA, Zusatzprogramme, Backups) beim ersten Hyprland-Start
    if [[ "$MODE" == target ]]; then
        ( cd "$repo" && source scripts/installs.sh && addFirstbootAutostart installISOFirstboot ) >/dev/null 2>&1 || true
    fi
    exit 0
fi

# --- Teil als root ---
U=${1:?Benutzer fehlt}
MODE=${2:-target}
H=$(getent passwd "$U" | cut -d: -f6)
[[ -n "$H" ]] || { echo "Benutzer $U nicht gefunden" >&2; exit 1; }
mkdir -p "$H/Bilder"
[[ -d "$H/sArch" ]] || cp -a "$SRC" "$H/sArch"
if [[ -d "$WP" && ! -e "$H/Bilder/Wallpapers" ]]; then
    if [[ "$MODE" == live ]]; then ln -sfnT "$WP" "$H/Bilder/Wallpapers"; else mv "$WP" "$H/Bilder/Wallpapers"; fi
fi
chown -R "$U:$U" "$H"
runuser -u "$U" -- env HOME="$H" USER="$U" LOGNAME="$U" bash "$0" --as-user "$MODE"
