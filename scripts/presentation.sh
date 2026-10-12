#!/bin/bash
## Omarchy-artige Darstellung: zentriertes Logo, fester Fortschrittsbalken in der
## Mitte und darunter ein gedimmter Live-Ausschnitt aus dem Install-Log.
##
## Bildschirmaufbau (alles horizontal zentriert, Block vertikal zentriert):
##
##   <Logo>
##
##   <Titel der Stage>            TITLE_ROW   (Menüs/Prompts starten hier)
##
## - ████████████░░░░░░░░░░░      BAR_ROW     (links davon ein Spinner)
##   <Aktueller Schritt>          LABEL_ROW
##
##   <letzte TAIL_LINES Log-Zeilen>  TAIL_ROW ...

# Breitenberechnung (${#str}) braucht eine UTF-8-Locale, sonst zählen Bytes
# (im frischen chroot ist z.B. noch keine Locale gesetzt).
[[ "$(locale charmap 2>/dev/null)" == UTF-8 ]] || export LC_CTYPE=C.UTF-8

sARCH_LOGO="${sARCH_LOGO:-$sARCH_MAIN/logo.txt}"
TAIL_LINES=${TAIL_LINES:-8}
_atBOL=1          # steht der Cursor am Zeilenanfang? (für die Einrückung in myPrint)
_TAIL_PID=""
_STAGE_ACTIVE=0
_STAGE=""

# Auf der Linux-Konsole (TTY) fehlen manche Glyphen (z.B. ❯) -> ASCII-Ersatz
if [[ "${TERM:-}" == linux ]]; then
    SEL_MARK=">"
else
    SEL_MARK="❯"
fi

# Einmalig: größere Konsolenschrift auf einem echten TTY (Terminus ist auf dem Arch-ISO)
_initConsole() {
    [[ -n "${_consoleDone:-}" ]] && return 0
    _consoleDone=1
    if [[ -n "${consoleFont:-}" && "$(tty 2>/dev/null)" == /dev/tty[0-9]* ]]; then
        setfont "$consoleFont" 2>/dev/null || true
    fi
    return 0
}

# Berechnet alle Positionen neu (bei jedem drawLogo -> passt sich an die Terminalgröße an)
_layout() {
    local r c l block
    read -r r c < <(stty size </dev/tty 2>/dev/null) || true
    ROWS=${r:-24}
    COLS=${c:-80}
    (( ROWS > 0 )) || ROWS=24
    (( COLS > 0 )) || COLS=80

    if [[ -r "$sARCH_LOGO" ]]; then
        mapfile -t _LOGO < "$sARCH_LOGO"
    else
        _LOGO=("sArch")
    fi
    LOGO_H=${#_LOGO[@]}
    LOGO_W=0
    for l in "${_LOGO[@]}"; do (( ${#l} > LOGO_W )) && LOGO_W=${#l}; done

    PAD=$(( (COLS - LOGO_W) / 2 ))
    (( PAD < 0 )) && PAD=0
    printf -v PADS '%*s' "$PAD" ''

    BAR_W=$LOGO_W
    (( BAR_W < 30 )) && BAR_W=30
    (( BAR_W > COLS - 6 )) && BAR_W=$(( COLS - 6 ))
    (( BAR_W < 10 )) && BAR_W=10
    BAR_COL=$(( (COLS - BAR_W) / 2 + 1 ))

    block=$(( LOGO_H + 6 + TAIL_LINES ))
    TOP=$(( (ROWS - block) / 2 + 1 ))
    (( TOP < 1 )) && TOP=1
    TITLE_ROW=$(( TOP + LOGO_H + 1 ))
    BAR_ROW=$(( TITLE_ROW + 2 ))
    LABEL_ROW=$(( BAR_ROW + 1 ))
    TAIL_ROW=$(( LABEL_ROW + 2 ))
    BODY_ROW=$TITLE_ROW
    return 0
}

# Bildschirm leeren, Logo zentriert zeichnen, Cursor auf den Anfang des Inhaltsbereichs
drawLogo() {
    local l out
    _initConsole
    _layout
    printf -v out '\033[2J\033[%d;1H' "$TOP"
    for l in "${_LOGO[@]}"; do
        out+="${PADS}${GREEN:-}${l}${NC:-}"$'\n'
    done
    printf '%b' "$out"
    printf '\033[%d;1H' "$BODY_ROW"
    _atBOL=1
    return 0
}

# Text in Zeile $1 zentriert ausgeben (Farbe $2, Text $3); Zeile wird vorher geleert
_printCentered() {
    local row=$1 color=$2 text=$3 col
    col=$(( (COLS - ${#text}) / 2 + 1 ))
    (( col < 1 )) && col=1
    printf '\033[%d;1H\033[2K\033[%d;%dH%b%s%b' "$row" "$row" "$col" "$color" "$text" "${NC:-}"
}

# drawProgress <cur> <max> [label]
drawProgress() {
    local cur=$1 max=$2 f i done_="" rest=""
    (( max < 1 )) && max=1
    (( cur < 0 )) && cur=0
    (( cur > max )) && cur=$max
    f=$(( cur * BAR_W / max ))
    for ((i = 0; i < f; i++)); do done_+='█'; done
    for ((i = f; i < BAR_W; i++)); do rest+='░'; done
    printf '\033[%d;%dH%b%s\033[90m%s%b' "$BAR_ROW" "$BAR_COL" "${GREEN:-}" "$done_" "$rest" "${NC:-}"
    [[ -n "${3+x}" ]] && _printCentered "$LABEL_ROW" "${WHITE:-}" "$3"
    return 0
}

# Hintergrundprozess: Spinner links vom Balken + letzte Log-Zeilen gedimmt darunter.
# Jeder Frame wird als EIN printf geschrieben, damit er sich nicht mit drawProgress vermischt.
startLogTail() {
    stopLogTail
    (
        trap 'exit 0' TERM
        shopt -s extglob
        local frames='|/-\' i=0 r line out
        local -a lines
        while :; do
            printf -v out '\033[%d;%dH%b%s%b' "$BAR_ROW" $(( BAR_COL - 2 )) "${GREEN:-}" "${frames:i++%4:1}" "${NC:-}"
            lines=()
            [[ -r "${logFile:-}" ]] && mapfile -t lines < <(tail -n "$TAIL_LINES" "$logFile" 2>/dev/null)
            for ((r = 0; r < TAIL_LINES; r++)); do
                line=${lines[r]:-}
                line=${line##*$'\r'}                              # pacman-Fortschritt: nur letzter Stand
                line=${line//$'\e'\[*([0-9;?])[a-zA-Z]/}          # ANSI-Farben entfernen
                line=${line//$'\t'/ }
                line=${line//[[:cntrl:]]/}
                printf -v line '\033[%d;%dH\033[2K\033[90m%s\033[0m' $(( TAIL_ROW + r )) "$BAR_COL" "${line:0:BAR_W}"
                out+=$line
            done
            printf '%s' "$out"
            sleep 0.25
        done
    ) </dev/null &
    _TAIL_PID=$!
    return 0
}

stopLogTail() {
    [[ -n "${_TAIL_PID:-}" ]] || return 0
    kill "$_TAIL_PID" 2>/dev/null
    wait "$_TAIL_PID" 2>/dev/null
    _TAIL_PID=""
    return 0
}

# Neue Stage: Logo, Titel, leerer Balken, Log-Tail starten
stageBegin() {
    drawLogo
    printf '\033[?25l'
    _STAGE="$*"
    _STAGE_ACTIVE=1
    _printCentered "$TITLE_ROW" "${WHITE:-}" "$_STAGE"
    drawProgress 0 1 ""
    startLogTail
    return 0
}

# Stage abschließen: Tail stoppen, Balken voll, Titel mit Haken
stageEnd() {
    (( _STAGE_ACTIVE )) || return 0
    stopLogTail
    printf '\033[%d;%dH ' "$BAR_ROW" $(( BAR_COL - 2 ))
    drawProgress 1 1 ""
    _printCentered "$TITLE_ROW" "${GREEN:-}" "✓ ${_STAGE}"
    _leaveStageScreen
    return 0
}

# Stage als fehlgeschlagen markieren (roter Titel, Spinner weg)
stageFail() {
    (( _STAGE_ACTIVE )) || return 0
    stopLogTail
    printf '\033[%d;%dH ' "$BAR_ROW" $(( BAR_COL - 2 ))
    _printCentered "$TITLE_ROW" "${RED:-}" "✗ ${_STAGE}"
    _leaveStageScreen
    return 0
}

# Cursor unter den Stage-Bereich setzen und wieder einblenden (auch bei Fehlern)
_leaveStageScreen() {
    stopLogTail
    if (( _STAGE_ACTIVE )); then
        printf '\033[%d;1H\n' $(( TAIL_ROW + TAIL_LINES ))
        _STAGE_ACTIVE=0
    fi
    printf '\033[?25h'
    _atBOL=1
    return 0
}

# Vorschau ohne Installation:  ./install.sh presentationDemo
presentationDemo() {
    local tmp i n
    tmp=$(mktemp)
    logFile=$tmp
    stageBegin "Installing Base system..."
    local -a steps=("Formatting drives..." "Mounting partitions..." "Setting up pacman..." "Running pacstrap...")
    local -a marks=(0 7 8 13 20)
    for i in "${!steps[@]}"; do
        drawProgress "${marks[i]}" 20 "${steps[i]}"
        for ((n = 0; n < 6; n++)); do
            printf '(%d/6) installing demo-package-%d-%d ...\n' $((n + 1)) "$i" "$n" >> "$logFile"
            sleep 0.3
        done
        drawProgress "${marks[i+1]}" 20
    done
    stageEnd
    rm -f "$tmp"
}
