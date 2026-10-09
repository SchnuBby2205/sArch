#!/bin/bash
# Erzeugt 100x100 Thumbnails für alle Wallpaper (nur neue oder geänderte Bilder)

wallpaperDir=$HOME/Bilder/Wallpapers/
cacheDir=$HOME/.cache/Wallpaper_thumbs/

mkdir -p "$cacheDir"
[[ -d "$wallpaperDir" ]] || exit 0

# ohne nullglob würde bei fehlenden PNGs/JPGs die Zeichenkette "*.png" verarbeitet
shopt -s nullglob nocaseglob

for src in "$wallpaperDir"*.jpg "$wallpaperDir"*.png; do
    fname=$(basename "$src")
    dst="$cacheDir$fname"

    if [[ ! -e "$dst" || "$src" -nt "$dst" ]]; then
        magick "$src" -thumbnail 100x100^ -gravity center -extent 100x100 -quality 75 "$dst"
    fi
done
