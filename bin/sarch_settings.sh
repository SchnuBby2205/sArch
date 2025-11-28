#!/usr/bin/env bash
dir="$HOME/.config/rofi/"
theme='power'
mode=$(echo -e "Hyprland\nDunst\nFont" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)

if [[ "$mode" == "Hyprland" ]]; then
	#submode=$(echo -e "hyprland\nkeybindings\nwindowrules" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)
	code "/home/schnubby/.config/hypr/"
fi

if [[ "$mode" == "Dunst" ]]; then
	submode=$(echo -e "Position" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)
	if [[ "$submode" == "Position" ]]; then
		setting=$(echo -e "top-left\ntop-center\ntop-right\nbottom-left\nbottom-center\nbottom-right\nleft-center\ncenter\nright-center" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)
		sed -i "s/^origin .*$/origin = ${setting}/" ~/.config/dunst/dunstrc
		sed -i "s/^origin .*$/origin = ${setting}/" ~/.config/matugen/templates/dunstrc.colors
		dunstctl reload
		dunstify -a "Themes" -u low -t 1000 -c "Dunst position changed" "${setting}" 
	fi
fi

if [[ "$mode" == "Font" ]]; then
	submode=$(echo -e "Family\nSize" | rofi -dmenu -theme ~/.config/rofi/launcher.rasi)
	if [[ "$submode" == "Family" ]]; then	
		returnDir=$PWD
		cd ~/.local/share/fonts
		font=$(for a in *.ttf *.otf; do
			fontname=$(fc-scan --format="%{family}\n" "$a")
			echo -e "$fontname"
		done | rofi -dmenu -theme gruvbox-material_icons.rasi)
		sed -i 's/^\(font[[:space:]]*=[[:space:]]*"\)[^"]* \([0-9]\+\)"/\1'"$font"' \2"/' ~/.config/dunst/dunstrc
		sed -i 's/^\(font[[:space:]]*=[[:space:]]*"\)[^"]* \([0-9]\+\)"/\1'"$font"' \2"/' ~/.config/matugen/templates/dunstrc.colors
		dunstctl reload
		sed -i 's/^\(mainfont:[[:space:]]*"\)[^"]* \([0-9]\+\)\(";*\)$/\1'"$font"' \2\3/' ~/.config/rofi/colors.rasi
		sed -i 's/^\(mainfont:[[:space:]]*"\)[^"]* \([0-9]\+\)\(";*\)$/\1'"$font"' \2\3/' ~/.config/matugen/templates/rofi-colors.rasi
		cd $returnDir 
		if [[ -n $font ]]; then
			dunstify -a "Themes" -u low -t 1000 -c "Font changed" "${font}" 
		fi
	fi
	if [[ "$submode" == "Size" ]]; then
		eingabe="$(rofi -dmenu -lines 0 -p "New Size:")"
		sed -i 's/\(font[[:space:]]*=[[:space:]]*"[^"]*\) [0-9]\+/\1 '"$eingabe"'/' ~/.config/dunst/dunstrc
		sed -i 's/\(font[[:space:]]*=[[:space:]]*"[^"]*\) [0-9]\+/\1 '"$eingabe"'/' ~/.config/matugen/templates/dunstrc.colors
		dunstctl reload
		sed -i 's/^\([[:space:]]*mainfont: "[^"]*\) [0-9]\+\(".*\)$/\1 '"$eingabe"'\2/' ~/.config/rofi/colors.rasi
		sed -i 's/^\([[:space:]]*mainfont: "[^"]*\) [0-9]\+\(".*\)$/\1 '"$eingabe"'\2/' ~/.config/matugen/templates/rofi-colors.rasi
		if [[ -n $eingabe ]]; then
			dunstify -a "Themes" -u low -t 1000 -c "Font size changed" "${eingabe}" 
		fi
	fi
fi