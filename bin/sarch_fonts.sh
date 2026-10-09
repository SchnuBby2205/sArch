#!/bin/bash
# font_rofi_preview.sh
# Aufruf: font_rofi_preview.sh [verzeichnis ...]
# Ohne Argument: ~/.local/share/fonts und /usr/share/fonts
# MONO_ONLY=1 font_rofi_preview.sh  -> nur Monospace-Fonts (für das Terminal)

DIRS=("$@")
[ ${#DIRS[@]} -eq 0 ] && DIRS=("$HOME/.local/share/fonts" "/usr/share/fonts")

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEXT="Test\n123"
THUMB_SIZE=128
POINTSIZE=32

declare -A FONTNAME_MAP
declare -A SEEN
i=0

while IFS= read -r -d '' f; do
    # Nur den Familiennamen (erster Name, ohne Stil) -> genau das wird in dunstrc/colors.rasi geschrieben
    fontname=$(fc-query -f "%{family[0]}\n" "$f" 2>/dev/null | head -n1)
    [ -n "$fontname" ] || continue
    # Nur Monospace (fontconfig-Spacing 100/110 oder typische Namen; Nerd-Fonts sind oft nicht als mono markiert)
    if [ -n "$MONO_ONLY" ]; then
        spacing=$(fc-query -f '%{spacing}' "$f" 2>/dev/null)
        if [[ "$spacing" != "100" && "$spacing" != "110" ]] && \
           ! [[ "$fontname" =~ ([Mm]ono|[Cc]ode|[Nn]erd|Iosevka|[Cc]ourier) ]]; then
            continue
        fi
    fi
    # Pro Familie nur eine Vorschau (Regular/Bold/Italic... sind dieselbe Familie)
    [ -n "${SEEN[$fontname]}" ] && continue
    SEEN["$fontname"]=1

    out_png="$TMP_DIR/$(printf '%05d' "$i").png"
    i=$((i + 1))

    magick -size ${THUMB_SIZE}x${THUMB_SIZE} -background white \
        -fill black -gravity center \
        -font "$f" -pointsize $POINTSIZE \
        label:"$TEXT" \
        -thumbnail ${THUMB_SIZE}x${THUMB_SIZE}^ -gravity center -extent ${THUMB_SIZE}x${THUMB_SIZE} \
        "$out_png" 2>/dev/null || continue

    FONTNAME_MAP["$out_png"]="$fontname"
done < <(find "${DIRS[@]}" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null | sort -z)

for img in "$TMP_DIR"/*.png; do
    [ -f "$img" ] || continue
    echo -en "${FONTNAME_MAP[$img]}\0icon\x1f$img\n"
done | rofi -dmenu -theme gruvbox-material_icons.rasi
