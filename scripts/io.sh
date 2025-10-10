#!/bin/bash
# @name Prompts
# @brief Inquirer.js inspired prompts

## Functions that output something or read something
Banner() {
  clear
  myPrint print green ".▄▄ ·  ▄▄·  ▄ .▄ ▐ ▄ ▄• ▄▌▄▄▄▄· ▄▄▄▄·  ▄· ▄▌            \n"
  myPrint print green "▐█ ▀. ▐█ ▌▪██▪▐█•█▌▐██▪██▌▐█ ▀█▪▐█ ▀█▪▐█▪██▌            \n"
  myPrint print green "▄▀▀▀█▄██ ▄▄██▀▐█▐█▐▐▌█▌▐█▌▐█▀▀█▄▐█▀▀█▄▐█▌▐█▪            \n"
  myPrint print green "▐█▄▪▐█▐███▌██▌▐▀██▐█▌▐█▄█▌██▄▪▐███▄▪▐█ ▐█▀·.            \n"
  myPrint print green " ▀▀▀▀ ·▀▀▀ ▀▀▀ ·▀▀ █▪ ▀▀▀ ·▀▀▀▀ ·▀▀▀▀   ▀ •             \n"
  myPrint print green " ▄▄▄· ▄▄▄   ▄▄·  ▄ .▄▪   ▐ ▄ .▄▄ · ▄▄▄▄▄ ▄▄▄· ▄▄▌  ▄▄▌  \n"
  myPrint print green "▐█ ▀█ ▀▄ █·▐█ ▌▪██▪▐███ •█▌▐█▐█ ▀. •██  ▐█ ▀█ ██•  ██•  \n"
  myPrint print green "▄█▀▀█ ▐▀▀▄ ██ ▄▄██▀▐█▐█·▐█▐▐▌▄▀▀▀█▄ ▐█.▪▄█▀▀█ ██▪  ██▪  \n"
  myPrint print green "▐█ ▪▐▌▐█•█▌▐███▌██▌▐▀▐█▌██▐█▌▐█▄▪▐█ ▐█▌·▐█ ▪▐▌▐█▌▐▌▐█▌▐▌\n"
  myPrint print green " ▀  ▀ .▀  ▀·▀▀▀ ▀▀▀ ·▀▀▀▀▀ █▪ ▀▀▀▀  ▀▀▀  ▀  ▀ .▀▀▀ .▀▀▀ \n\n"
}
#TESTEN: function myPrint() { local c=$1 m=$2; printf "%b" "${!c^^}${m}${NC:-}"; }
myPrint(){ case "$1" in
  step) [ "$2" = ok ] && printf "${CLEAR}${UP}${CLEAR}" || printf "${RUNNING} $2 ${WHITE}$3${NC}\n";;
  countdown) for((i=$2;i>0;i--));do myPrint print green "\r$3 $i..."; sleep 1; done; echo;;
  print) c=${2^^}; printf "%b" "${!c}${3}${NC:-}";;  
esac; }
exitWithError() { printf "\n${ERROR} %s\n" "$1"; exit 1; }
getInput(){ local p=$1 v=$2 d=$3 i; printf "${YELLOW}${p} ${NC}"; read -r i; printf -v "$v" "%s" "${i:-$d}"; [[ -z "${!v}" ]] && exitWithError "Input value can not be empty!"; }
myPasswd() {
  for ((a=0; a<3; a++)); do
    read -s -p "Password: " p1; echo
    read -s -p "Retype: " p2; echo
    [[ "$p1" != "$p2" || -z "$p1" ]] && echo "Passwords didn't match." && continue
    echo "$1:$p1" | sudo chpasswd && { myPrint print yellow "\nPassword updated successfully.\n"; return; }
    exitWithError "Error setting the password."
  done
  myPrint print red "Maximum tries reached. Script will end now."; exit 1
}
log() { }#echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$logFile"; }
addToBashrc() { grep -qxF "$1" $HOME/.bashrc || echo "$1" >> $HOME/.bashrc; }
readList(){ { read -r name; read -r value; mapfile -t list; } < "$1"; }
_read_stdin() {
	# shellcheck disable=SC2162,SC2068
	read $@ </dev/tty
}
_get_cursor_row() {
    local IFS=';'
    # shellcheck disable=SC2162,SC2034
    _read_stdin -sdR -p $'\E[6n' ROW COL;
    echo "${ROW#*[}";
}
_cursor_blink_on() { echo -en "\033[?25h" >&2; }
_cursor_blink_off() { echo -en "\033[?25l" >&2; }
_cursor_to() { echo -en "\033[$1;$2H" >&2; }
_key_input() {
    local ESC=$'\033'
    local IFS=''

    _read_stdin -rsn1 a
    # is the first character ESC?
	# shellcheck disable=SC2154
    if [[ "$ESC" == "$a" ]]; then
        _read_stdin -rsn2 b
    fi

	# shellcheck disable=SC2154
    local input="${a}${b}"
    # shellcheck disable=SC1087
    case "$input" in
        "$ESC[A" | "k") echo up ;;
        "$ESC[B" | "j") echo down ;;
        "$ESC[C" | "l") echo right ;;
        "$ESC[D" | "h") echo left ;;
        '') echo enter ;;
        ' ') echo space ;;
    esac
}
_new_line_foreach_item() {
    count=0
    while [[ $count -lt $1  ]];
    do
        echo "" >&2
        ((count++))
    done
}
# display prompt text without linebreak
_prompt_text() {
    echo -en "\033[32m?${NC}${YELLOW} ${1}${NC} " >&2
}

# decrement counter $1, considering out of range for $2
_decrement_selected() {
    local selected=$1;
    ((selected--))
    if [ "${selected}" -lt 0 ]; then
        selected=$(($2 - 1));
    fi
    echo -n $selected
}

# increment counter $1, considering out of range for $2
_increment_selected() {
    local selected=$1;
    ((selected++));
    if [ "${selected}" -ge "${opts_count}" ]; then
        selected=0;
    fi
    echo -n $selected
}

list() {
    _prompt_text "$1 "

    local opts=("${@:2}")
    local opts_count=$(($# -1))
    _new_line_foreach_item "${#opts[@]}"

    # determine current screen position for overwriting the options
    local lastrow; lastrow=$(_get_cursor_row)
    local startrow; startrow=$((lastrow - opts_count + 1))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "_cursor_blink_on; stty echo; exit" 2
    _cursor_blink_off

    local selected=0
    while true; do
        # print options by overwriting the last lines
        local idx=0
        for opt in "${opts[@]}"; do
            _cursor_to $((startrow + idx))
            if [ "$idx" -eq "$selected" ]; then
                printf "\033[0m\033[36m❯\033[0m \033[36m%s\033[0m" "$opt" >&2
            else
                printf "  %s" "$opt" >&2
            fi
            ((idx++))
        done

        # user key control
        case $(_key_input) in
            enter) break; ;;
            up) selected=$(_decrement_selected "${selected}" "${opts_count}"); ;;
            down) selected=$(_increment_selected "${selected}" "${opts_count}"); ;;
        esac
    done

    echo -en "\n" >&2

    # cursor position back to normal
    _cursor_to "${lastrow}"
    _cursor_blink_on

    echo -n "${selected}"
}
main() {
    Banner
    choice=$(list "Main Menu" ${menuEntries[@]})
    if [[ ${menuEntries[$choice]} == "Settings" ]]; then showSettings; fi
    if [[ ${menuEntries[$choice]} == "Install" ]]; then
        clear
        Banner
        installentries=("Base System" "Arch-Chroot" "Desktop" "Configs" "Backups" "Back")
        installchoice=$(list "Install" "${installentries[@]}")
        if [[ "${installentries[$installchoice]}" == "Back" ]]; then            
            main
        else
            if [[ "${installentries[$installchoice]}" == "Base System" ]]; then installBaseSystem; fi
            if [[ "${installentries[$installchoice]}" == "Arch-Chroot" ]]; then installArchCHRoot; fi
            if [[ "${installentries[$installchoice]}" == "Desktop" ]]; then installDE; fi
            if [[ "${installentries[$installchoice]}" == "Configs" ]]; then installConfigs; fi
            if [[ "${installentries[$installchoice]}" == "Backups" ]]; then installBackup; fi
        fi
    fi
    if [[ ${menuEntries[$choice]} == "Exit" ]]; then clear; exit 0; fi
}
showSettings() {
    clear
    Banner
    entries=(
        "boot=$boot"
        "swap=$swap"
        "root=$root"
        "hostname=$hostname"
        "user=$user"
        "cpu=$cpu"
        "gpu=$gpu"
        "timezone=$timezone"
        "locale=$locale"
        "keymap=$keymap"
        "kernel=$kernel"
        "Back"
    )
    choice=$(list "Settings" ${entries[@]})
    if [[ "${entries[$choice]}" == "Back" ]]; then
        main
    else
        checkInstallSettings "${entries[$choice]%=*}"
    fi
}
