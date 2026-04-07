#!/bin/bash

~/.config/sArch/bin/sarch_create_thumbnails.sh

wallpaperDir=$HOME/Bilder/Wallpapers/
cacheDir=$HOME/.cache/Wallpaper_thumbs/
returnDir=$PWD

cd $cacheDir

wallpaper=$(for a in *.jpg *.png; do
    echo -en "$a\0icon\x1f$a\n"
    #echo $a
done | rofi -dmenu -theme gruvbox-material_icons.rasi)

tmpfile=$(mktemp)
script -q -c "timeout 1 matugen image '${wallpaperDir}${wallpaper}' --dry-run 2>&1; true" "$tmpfile" > /dev/null
colors=$(cat "$tmpfile" | grep -oP '#[0-9A-Fa-f]{6}' | head -5)
rm "$tmpfile"

# Farbige Icons generieren und rofi-Einträge bauen
icondir=$(mktemp -d)
rofi_input=""
i=0
while IFS= read -r color; do
    iconfile="${icondir}/${i}.png"
    magick -size 32x32 xc:"${color}" "${iconfile}"
    rofi_input+="${i}: ${color}\0icon\x1f${iconfile}\n"
    ((i++))
done <<< "$colors"

selected=$(echo -e "$rofi_input" | rofi -dmenu -p "Source Color" -theme gruvbox-material_icons.rasi)
color_index=$(echo "$selected" | grep -oP '^\d+')
color_index=${color_index:-0}

rm -rf "$icondir"

matugen image "${wallpaperDir}${wallpaper}" --source-color-index "${color_index}"

#matugen image ${wallpaperDir}${wallpaper} --source-color-index 0

magick "${wallpaperDir}${wallpaper}" -thumbnail 500x500^ -gravity center -extent 500x500 -quality 70 "${cacheDir}curr"
magick "${wallpaperDir}${wallpaper}" -thumbnail 1000x500^ -gravity center -extent 1000x500 -quality 70 "${cacheDir}curr_wide"
#sed -i ':a;$!N;$!ba;s/,\s*}/}/' ~/.config/quickshell/myShell/Configs/colors.json

if [[ -n "$wallpaper" ]]; then
    dunstify -a "Themes" -u low -t 1000 -c "Wallpaper changed" "${wallpaper}"
fi

cd $returnDir
#/bin/reload_shell.sh
