#!/usr/bin/env bash
# Wechselt den Workspace (von der Quickshell-Bar aufgerufen).
#   sarch_workspace.sh 3      -> Workspace 3
#   sarch_workspace.sh e+1    -> nächster belegter Workspace (e-1 = vorheriger)
# Probiert der Reihe nach die klassische Dispatcher-Syntax und die Lua-Varianten,
# da sich die IPC-Syntax mit der Lua-Konfiguration geändert haben kann.
ws="${1:?Workspace fehlt}"
log="$HOME/.cache/sArch/bar-dispatch.log"

if [[ "$ws" =~ ^[0-9]+$ ]]; then lua="$ws"; else lua="\"$ws\""; fi

attempt() {
    out=$("$@" 2>&1)
    [[ "${out,,}" == ok* ]]
}

attempt hyprctl dispatch workspace "$ws" && exit 0
first="$out"
attempt hyprctl dispatch "hl.dsp.focus({ workspace = $lua })" && exit 0
second="$out"
attempt hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $lua }))" && exit 0

mkdir -p "${log%/*}"
{
    echo "$(date '+%F %T') workspace $ws fehlgeschlagen"
    echo "  dispatch workspace: $first"
    echo "  dispatch lua:       $second"
    echo "  eval lua:           $out"
} >> "$log"
exit 1
