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

matugen image ${wallpaperDir}${wallpaper}
magick "${wallpaperDir}${wallpaper}" -thumbnail 500x500^ -gravity center -extent 500x500 -quality 70 "${cacheDir}curr"
magick "${wallpaperDir}${wallpaper}" -thumbnail 1000x500^ -gravity center -extent 1000x500 -quality 70 "${cacheDir}curr_wide"
sed -i ':a;$!N;$!ba;s/,\s*}/}/' ~/.config/quickshell/myShell/Configs/colors.json

cd $returnDir
#/bin/reload_shell.sh
