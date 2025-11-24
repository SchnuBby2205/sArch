#!/bin/bash

wallpaperDir=$HOME/Bilder/Wallpapers/
cacheDir=$HOME/.cache/Wallpaper_thumbs/
returnDir=$PWD

mkdir -p $cacheDir

cd $wallpaperDir || exit 0

for i in *.jpg *.png; do 
    fname=$(basename "$i")
    dst="$cacheDir/$fname"
    
    if [[ ! -e "$dst" || "$src" -nt "$dst" ]]; then
        #echo -e "converting: $fname"
        magick "$wallpaperDir$i" -thumbnail 100x100^ -gravity center -extent 100x100 -quality 75 "$cacheDir$fname"
    #else
       #echo -e "skipping: $fname"
    fi
done

cd $returnDir
