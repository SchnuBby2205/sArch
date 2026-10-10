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

myPrint() {
    local c i
    case "$1" in
        step)
            if [ "$2" = ok ]; then
                printf '%b%b%b' "${CLEAR:-}" "${UP:-}" "${CLEAR:-}"
            else
                printf '%b %b %b%b%b\n' "${RUNNING:-}" "$2" "${WHITE:-}" "$3" "${NC:-}"
            fi
            ;;
        countdown)
            for ((i = $2; i > 0; i--)); do
                myPrint print green "\r$3 $i..."
                sleep 1
            done
            echo
            ;;
        print)
            c=${2^^}
            printf '%b' "${!c:-}${3}${NC:-}"
            ;;
    esac
    return 0
}

# Fehlermeldung auf stderr, dann Skript beenden.
# ACHTUNG: In $(...) beendet exit nur die Subshell, nicht das Hauptskript.
exitWithError() {
    printf '\n%b %b\n' "${ERROR:-ERROR:}" "$1" >&2
    exit 1
}

# getInput "Prompt" variablenname [default]
getInput() {
    local _gi_p=$1 _gi_v=$2 _gi_d=${3:-} _gi_i
    printf '%b%b %b' "${YELLOW:-}" "$_gi_p" "${NC:-}"
    read -r _gi_i
    printf -v "$_gi_v" '%s' "${_gi_i:-$_gi_d}"
    [[ -z "${!_gi_v}" ]] && exitWithError "Input value can not be empty!"
    return 0
}

# myPasswd <user>
myPasswd() {
    local target=$1 p1 p2 a
    [[ -z "$target" ]] && exitWithError "myPasswd: no user given"
    for ((a = 0; a < 3; a++)); do
        read -rs -p "Password: " p1; echo
        read -rs -p "Retype: " p2; echo
        if [[ -z "$p1" || "$p1" != "$p2" ]]; then
            echo "Passwords didn't match."
            continue
        fi
        if printf '%s:%s\n' "$target" "$p1" | sudo chpasswd; then
            unset p1 p2
            myPrint print yellow "\nPassword updated successfully.\n"
            return 0
        fi
        unset p1 p2
        exitWithError "Error setting the password."
    done
    unset p1 p2
    myPrint print red "Maximum tries reached. Script will end now.\n"
    exit 1
}

# Schreibt nur, wenn $logFile gesetzt ist. Gibt immer 0 zurück.
log() {
    if [[ -n "${logFile:-}" ]]; then
        printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$logFile"
    fi
    return 0
}

addToBashrc() {
    local rc="${HOME}/.bashrc"
    touch "$rc"
    grep -qxF -- "$1" "$rc" || printf '%s\n' "$1" >> "$rc"
    return 0
}

# Liest eine Listendatei: Zeile 1 -> name, Zeile 2 -> value, Rest -> Array "list"
# (name/value bleiben global, falls andere Skripte sie benutzen)
readList() {
    local f=$1 line
    local -a raw=()
    [[ -r "$f" ]] || exitWithError "List file not found: $f"
    { read -r name; read -r value; mapfile -t raw; } < "$f"
    list=()
    for line in "${raw[@]}"; do
        [[ -n "$line" ]] && list+=("$line")
    done
    return 0
}

_read_stdin() {
    # shellcheck disable=SC2162
    read "$@" </dev/tty
}

_cursor_blink_on()  { echo -en "\033[?25h" >&2; }
_cursor_blink_off() { echo -en "\033[?25l" >&2; }

# Liefert: up down left right enter space pgup pgdn home end (oder nichts)
_key_input() {
    local ESC=$'\033' IFS='' a='' b='' c=''
    _read_stdin -rsn1 a
    if [[ "$a" == "$ESC" ]]; then
        _read_stdin -rsn2 -t 0.05 b
    fi
    case "${a}${b}" in
        "${ESC}[A" | "k") echo up ;;
        "${ESC}[B" | "j") echo down ;;
        "${ESC}[C" | "l") echo right ;;
        "${ESC}[D" | "h") echo left ;;
        "${ESC}[5") _read_stdin -rsn1 -t 0.05 c; echo pgup ;;
        "${ESC}[6") _read_stdin -rsn1 -t 0.05 c; echo pgdn ;;
        "${ESC}[H") echo home ;;
        "${ESC}[F") echo end ;;
        '') echo enter ;;
        ' ') echo space ;;
    esac
}

_term_size() {
    local r c
    read -r r c < <(stty size </dev/tty 2>/dev/null) || true
    echo "${r:-24} ${c:-80}"
}

# list "Prompt" opt1 opt2 ...   -> gibt den INDEX der Auswahl auf stdout aus
# Läuft in eigener Subshell (Traps/Terminalzustand bleiben lokal), unterstützt
# Scrolling bei langen Listen und bricht bei Ctrl+C das Hauptskript ab.
list() {
    (
        local prompt=$1
        shift
        local -a opts=("$@")
        local n=${#opts[@]}
        (( n > 0 )) || exit 1

        local rows cols maxvis visible footer=0 top=0 selected=0 i idx
        read -r rows cols <<< "$(_term_size)"
        maxvis=$((rows - 3))
        (( maxvis < 3 )) && maxvis=3
        visible=$n
        if (( n > maxvis )); then visible=$maxvis; footer=1; fi
        local height=$((visible + footer)) width=$((cols - 4))
        (( width < 10 )) && width=10

        trap '_cursor_blink_on; stty echo </dev/tty 2>/dev/null' EXIT
        trap 'kill -s INT "$$"; exit 130' INT

        echo -en "\033[32m?${NC:-}${YELLOW:-} ${prompt}${NC:-}\n" >&2
        _cursor_blink_off

        local first=1
        while true; do
            (( first )) || printf '\033[%dA' "$height" >&2
            first=0
            for ((i = 0; i < visible; i++)); do
                idx=$((top + i))
                printf '\r\033[2K' >&2
                if (( idx == selected )); then
                    printf '\033[36m❯ %s\033[0m\n' "${opts[idx]:0:width}" >&2
                else
                    printf '  %s\n' "${opts[idx]:0:width}" >&2
                fi
            done
            if (( footer )); then
                printf '\r\033[2K\033[2m  (%d/%d)\033[0m\n' "$((selected + 1))" "$n" >&2
            fi

            case "$(_key_input)" in
                enter) break ;;
                up)    selected=$(( (selected - 1 + n) % n )) ;;
                down)  selected=$(( (selected + 1) % n )) ;;
                pgup)  selected=$(( selected - visible < 0 ? 0 : selected - visible )) ;;
                pgdn)  selected=$(( selected + visible > n - 1 ? n - 1 : selected + visible )) ;;
                home)  selected=0 ;;
                end)   selected=$((n - 1)) ;;
            esac
            (( selected < top )) && top=$selected
            (( selected >= top + visible )) && top=$((selected - visible + 1))
        done

        # Auswahlblock entfernen, nur die gewählte Zeile stehen lassen
        printf '\033[%dA\033[J' "$height" >&2
        printf '\033[36m❯ %s\033[0m\n' "${opts[selected]:0:width}" >&2
        printf '%s' "$selected"
    )
}

# Schreibt KEY=<rhs> in install_settings (ersetzt die Zeile oder hängt sie an).
# rhs wird roh geschrieben, der Aufrufer sorgt fürs Quoting.
_writeSetting() { # $1 = Name, $2 = rechte Seite
    local f="$sARCH_INSTALLCONFIGS/install_settings" rhs=$2
    rhs=${rhs//\\/\\\\}; rhs=${rhs//&/\\&}; rhs=${rhs//|/\\|}
    if grep -q "^$1=" "$f"; then
        sed -i "s|^$1=.*|$1=$rhs|" "$f"
    else
        printf '%s=%s\n' "$1" "$2" >> "$f"
    fi
}

# Prüft einen neuen Wert: *_DEV muss ein existierendes Blockgerät sein,
# alles andere (Mountpoints, Verzeichnisse) ein absoluter Pfad.
_validateSetting() { # $1 = Name, $2 = Wert
    case "$1" in
        *_DEV) [[ -b "$2" ]] \
                   || { myPrint print red "'$2' ist kein vorhandenes Blockgerät - nicht übernommen.\n"; return 1; } ;;
        *)     [[ "$2" == /* ]] \
                   || { myPrint print red "'$2' ist kein absoluter Pfad - nicht übernommen.\n"; return 1; } ;;
    esac
}

# BACKUP_*/GAMES_*-Variable abfragen, prüfen, setzen und in install_settings speichern
setPathSetting() { # $1 = BACKUP_DEV|BACKUP_MNT|BACKUP_DIR|GAMES_DEV|GAMES_MNT
    local var=$1 val oldmnt=$BACKUP_MNT
    getInput "New value for $var [${!var}]:" val "${!var}"
    [[ "$val" != "/" ]] && val=${val%/}
    if ! _validateSetting "$var" "$val"; then
        sleep 2     # sonst löscht das Banner im Menü die Fehlermeldung sofort
        return 1
    fi
    printf -v "$var" '%s' "$val"
    _writeSetting "$var" "$(printf '%q' "$val")"
    # War BACKUP_DIR abgeleitet, bei neuem Mountpoint mitziehen
    if [[ "$var" == BACKUP_MNT && "$BACKUP_DIR" == "$oldmnt/backups" ]]; then
        BACKUP_DIR="$BACKUP_MNT/backups"
        _writeSetting BACKUP_DIR '"$BACKUP_MNT/backups"'
    fi
}

_installMenu() {
    local sub
    local -a entries=("Base System" "Arch-Chroot" "Desktop" "Configs" "Backups" "Back")
    Banner
    sub=$(list "Install" "${entries[@]}") || return 1
    case "${entries[$sub]}" in
        "Base System") installBaseSystem ;;
        "Arch-Chroot") installArchCHRoot ;;
        "Desktop")     installDE ;;
        "Configs")     installConfigs ;;
        "Backups")     installBackup ;;
        "Back")        return 0 ;;
    esac
    return 0
}

# Hauptmenü als Schleife (keine Rekursion, lokales choice)
main() {
    local choice
    while true; do
        Banner
        choice=$(list "Main Menu" "${menuEntries[@]}") || return 1
        case "${menuEntries[$choice]}" in
            Settings) showSettings ;;
            Install)  _installMenu ;;
            Exit)     clear; exit 0 ;;
        esac
    done
}

# Einstellungsmenü als Schleife; "Back" kehrt zum Aufrufer zurück
showSettings() {
    local choice
    local -a entries
    while true; do
        Banner
        entries=(
            "boot=${boot:-}"
            "swap=${swap:-}"
            "root=${root:-}"
            "hostname=${hostname:-}"
            "user=${user:-}"
            "cpu=${cpu:-}"
            "gpu=${gpu:-}"
            "timezone=${timezone:-}"
            "locale=${locale:-}"
            "keymap=${keymap:-}"
            "kernel=${kernel:-}"
            "BACKUP_DEV=${BACKUP_DEV:-}"
            "BACKUP_MNT=${BACKUP_MNT:-}"
            "BACKUP_DIR=${BACKUP_DIR:-}"
            "GAMES_DEV=${GAMES_DEV:-}"
            "GAMES_MNT=${GAMES_MNT:-}"
            "Back"
        )
        choice=$(list "Settings" "${entries[@]}") || return 1
        [[ "${entries[$choice]}" == "Back" ]] && return 0
        case "${entries[$choice]%%=*}" in
            BACKUP_*|GAMES_*) setPathSetting "${entries[$choice]%%=*}" ;;
            *)        checkInstallSettings "${entries[$choice]%%=*}" ;;
        esac
    done
}
