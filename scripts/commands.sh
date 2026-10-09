## Functions that run commands or alter the script run aka "dry run"

# Maskiert Befehle, die Zugangsdaten enthalten könnten, für Ausgabe/Log
_cmdForDisplay() {
    if [[ "$1" == *passwd* || "$1" == *password* ]]; then
        printf '%s' "(command hidden, may contain credentials)"
    else
        printf '%s' "$1"
    fi
}

# Zeichnet "[####    ]" mit $1 gefüllten von $2 Stellen
_progressBar() {
    local f=$1 m=$2 i
    printf '['
    for ((i = 0; i < f; i++)); do printf '#'; done
    for ((i = f; i < m; i++)); do printf ' '; done
    printf ']'
}

# runCMDS <sudo:0|1> <icon/prefix> <message> <cur> <fin> <max> cmd...
# Optional: sARCH_PIPEFAIL=1 setzen, um die Befehle mit "set -o pipefail" auszuführen.
runCMDS() {
    (( $# >= 6 )) || exitWithError "runCMDS: expected at least 6 arguments"
    local s=$1 m=$2 msg=$3 cur=$4 fin=$5 max=$6 c
    shift 6
    local -a pre=() opts=()
    [[ "$s" == 1 ]] && pre=(sudo)
    [[ "${sARCH_PIPEFAIL:-0}" == 1 ]] && opts=(-o pipefail)

    if [[ "${debug:-}" != true ]]; then
        (( cur > 0 )) && printf '%b%b%b' "${CLEAR:-}" "${UP:-}" "${CLEAR:-}"
        _progressBar "$cur" "$max"
        printf '\n%b %b%b%b' "$m" "${WHITE:-}" "$msg" "${NC:-}"
    fi

    for c in "$@"; do
        "${pre[@]}" bash "${opts[@]}" -c "$c" \
            || exitWithError "Command failed: $(_cmdForDisplay "$c")"
    done

    if [[ "${debug:-}" != true ]]; then
        printf '%b\r' "${UP:-}"
        _progressBar "$fin" "$max"
        printf '\n'
    fi
    return 0
}

# safeCMD rm|mv ...  -> prüft das erste Nicht-Options-Argument (Quelle) auf Existenz
# safeCMD <anderer befehl> ... -> führt aus, bricht bei Fehler ab
safeCMD() {
    local cmd=$1 f src=""
    shift
    if [[ "$cmd" == rm || "$cmd" == mv ]]; then
        for f in "$@"; do
            [[ "$f" == -* ]] || { src=$f; break; }
        done
        if [[ -n "$src" && ! -e "$src" && ! -L "$src" ]]; then
            myPrint print yellow "Warning: $src doesnt exist, skipping $cmd.\n"
            log "Warning: $src doesnt exist, skipping $cmd."
            return 0
        fi
    fi
    if ! "$cmd" "$@"; then
        myPrint print red "Error: $cmd $* failed.\n"
        log "Error: $cmd $* failed."
        exitWithError "$cmd fehlgeschlagen für $*"
    fi
    return 0
}

# dryRun <befehl ...>: bei dryRun=true nur ausgeben/loggen, sonst ausführen
dryRun() {
    if [[ "${dryRun:-}" == true ]]; then
        echo "[DRY RUN]: $*"
        log "[DRY RUN]: $*"
        return 0
    fi
    "$@"
}
