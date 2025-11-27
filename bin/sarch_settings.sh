#!/usr/bin/env bash
dir="$HOME/.config/rofi/"
theme='power'
mode=$(echo -e "hypr\ndunst\nfont" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)

if [[ "$mode" == "hypr" ]]; then
	#submode=$(echo -e "hyprland\nkeybindings\nwindowrules" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)
	code "/home/schnubby/.config/hypr/"
fi

if [[ "$mode" == "dunst" ]]; then
	submode=$(echo -e "origin" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)
	if [[ "$submode" == "origin" ]]; then
		setting=$(echo -e "top-left\ntop-center\ntop-right\nbottom-left\nbottom-center\nbottom-right\nleft-center\ncenter\nright-center" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)
		sed -i "s/^origin .*$/origin = ${setting}/" ~/.config/dunst/dunstrc
		sed -i "s/^origin .*$/origin = ${setting}/" ~/.config/matugen/templates/dunstrc.colors
		dunstctl reload
		dunstify -a "Themes" -u low -t 1000 -c "Dunst origin changed" "${setting}" 
	fi
fi

if [[ "$mode" == "font" ]]; then
	# verziechnis einlesen und basename ausgeben demnach wählen
	# dunst und rofi und matugen
fi