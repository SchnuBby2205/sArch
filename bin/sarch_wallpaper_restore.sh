#!/bin/bash
# Setzt beim Start das zuletzt gewählte Wallpaper (~/.cache/sArch/current_wallpaper),
# wenn awww noch keins anzeigt (frisches System, ISO). awww merkt sich sonst selbst das letzte Bild.
state="$HOME/.cache/sArch/current_wallpaper"
[[ -s "$state" ]] || exit 0
wp=$(head -n1 "$state")
[[ -f "$wp" ]] || exit 0
for _ in {1..20}; do awww query &>/dev/null && break; sleep 0.25; done
awww query 2>/dev/null | grep -q 'image:' && exit 0
exec awww img --transition-type center --transition-step 15 --transition-fps 60 "$wp"
