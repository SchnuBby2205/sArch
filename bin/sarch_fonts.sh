#!/bin/bash
# font_rofi_preview.sh
# Zeigt alle TTF/OTF Fonts in einem Verzeichnis als Rofi-Menü mit Thumbnails

FONT_DIR="${1:-.}"
TMP_DIR="$(mktemp -d)"
TEXT="Test\n123"
THUMB_SIZE=128
POINTSIZE=32

declare -A FONTNAME_MAP

returnDir=$PWD
cd ~/.local/share/fonts

# Thumbnails erstellen
for f in *.ttf *.otf; do
    [ -f "$f" ] || continue
    base_name="$(basename "$f" | sed 's/\.[^.]*$//')"
    out_png="$TMP_DIR/${base_name}.png"

    # Thumbnail erzeugen
    magick -size ${THUMB_SIZE}x${THUMB_SIZE} -background white \
        -fill black -gravity center \
        -font "$(realpath "$f")" -pointsize $POINTSIZE \
        label:"$TEXT" \
        -thumbnail ${THUMB_SIZE}x${THUMB_SIZE}^ -gravity center -extent ${THUMB_SIZE}x${THUMB_SIZE} \
        "$out_png"

    # Tatsächlichen Fontnamen auslesen
    fontname=$(fc-query -f "%{family}\n" "$f" | head -n1)
    FONTNAME_MAP["$out_png"]="$fontname"
done

# Rofi-Menü anzeigen
for img in "$TMP_DIR"/*.png; do
    name="${FONTNAME_MAP[$img]}"
    echo -en "$name\0icon\x1f$img\n"
done | rofi -dmenu -theme gruvbox-material_icons.rasi

# Optional Temp löschen
rm -rf "$TMP_DIR"

cd "$returnDir"