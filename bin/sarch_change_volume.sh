#!/bin/bash
# changeVolume

# Arbitrary but unique message tag
msgTag="myvolume"
mode="$1"
out=""

#volume="$(amixer -c 0 get Master | tail -1 | awk '{print $4}' | sed 's/[^0-9]*//g')"
mute="$(amixer -c 0 get Master | tail -1 | awk '{print $6}' | sed 's/[^a-z]*//g')"

if [[ "$mode" == "toggle" && "$mute" == "on" ]]; then
    out="mute"
    amixer -D pulse sset Master mute
elif [[ "$mode" == "toggle" && "$mute" == "off" ]]; then
    out="unmute"
    amixer -D pulse sset Master unmute
else    
    amixer -D pulse sset Master "$@" > /dev/null
fi    

volume="$(amixer -D pulse get Master | tail -1 | awk '{print $5}' | sed 's/[^0-9]*//g')"

if [[ "$out" == "mute" ]]; then
    dunstify -a "Media" -c "Volume" -u low "Mute" -t 1000
else
    #dunstify -a "Media" -c "Volume" -u low -i audio-volume-high -t 1000 -h string:x-dunst-stack-tag:$msgTag -h int:value:"$volume" "Volume: ${volume}%"
    dunstify -a "Media" -c "Volume" -u low -t 1000 -h string:x-dunst-stack-tag:$msgTag -h int:value:"$volume" "Volume: ${volume}%"
fi