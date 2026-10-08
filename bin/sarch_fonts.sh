#!/bin/bash
# font_rofi_preview.sh
# Aufruf: font_rofi_preview.sh [verzeichnis ...]
# Ohne Argument: ~/.local/share/fonts und /usr/share/fonts

DIRS=("$@")
[ ${#DIRS[@]} -eq 0 ] && DIRS=("$HOME/.local/share/fonts" "/usr/share/fonts")

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEXT="Test\n123"
THUMB_SIZE=128
POINTSIZE=32

declare -A FONTNAME_MAP
i=0

while IFS= read -r -d '' f; do
    out_png="$TMP_DIR/$(printf '%05d' "$i").png"
    i=$((i + 1))

    magick -size ${THUMB_SIZE}x${THUMB_SIZE} -background white \
        -fill black -gravity center \
        -font "$f" -pointsize $POINTSIZE \
        label:"$TEXT" \
        -thumbnail ${THUMB_SIZE}x${THUMB_SIZE}^ -gravity center -extent ${THUMB_SIZE}x${THUMB_SIZE} \
        "$out_png" 2>/dev/null || continue

    fontname=$(fc-query -f "%{family} (%{style})\n" "$f" | head -n1)
    FONTNAME_MAP["$out_png"]="$fontname"
done < <(find "${DIRS[@]}" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null | sort -z)

for img in "$TMP_DIR"/*.png; do
    [ -f "$img" ] || continue
    echo -en "${FONTNAME_MAP[$img]}\0icon\x1f$img\n"
done | rofi -dmenu -theme gruvbox-material_icons.rasi
