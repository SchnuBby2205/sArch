#!/usr/bin/env bash
# Apps im Launcher aus-/einblenden – über eine eigene Kopie der .desktop-Datei mit NoDisplay=true
# unter ~/.local/share/applications (hat Vorrang vor der Systemdatei, übersteht Paket-Updates).
#   sarch_app_hide.sh hide <desktop-id>     z. B. btop  oder  btop.desktop
#   sarch_app_hide.sh show <desktop-id>
#   sarch_app_hide.sh list
# Liste der ausgeblendeten IDs: ~/.config/sArch/hidden-apps (liest der Launcher)
set -u
act=${1:-}
id=${2:-}
id=${id%.desktop}
user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
list="$HOME/.config/sArch/hidden-apps"
mkdir -p "$user_dir" "${list%/*}"
touch "$list"

if [[ "$act" == list ]]; then
    cat "$list"
    exit 0
fi
[[ "$act" =~ ^(hide|show)$ && -n "$id" && "$id" != */* ]] || { echo "Aufruf: $0 hide|show <desktop-id>" >&2; exit 2; }
dst="$user_dir/$id.desktop"

find_src() {
    local d
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for d in "${dirs[@]}"; do
        [[ -f "$d/applications/$id.desktop" ]] && { echo "$d/applications/$id.desktop"; return 0; }
        # Unterordner: kde-org.foo.desktop liegt als applications/kde/org.foo.desktop
        local sub="$d/applications/${id/-//}.desktop"
        [[ -f "$sub" ]] && { echo "$sub"; return 0; }
    done
    return 1
}

# NoDisplay im Abschnitt [Desktop Entry] setzen/entfernen (andere Abschnitte bleiben unberührt)
#   $1 = hide|show, $2 = Markerzeile ("" = keine)
rewrite() {
    local tmp
    tmp=$(mktemp) || exit 1
    awk -v mode="$1" -v marker="$2" '
        /^\[/ {
            main = ($0 == "[Desktop Entry]")
            print
            if (main && mode == "hide") {
                print "NoDisplay=true"
                if (marker != "") print marker
            }
            next
        }
        main && /^NoDisplay[[:space:]]*=/ { next }
        main && /^X-sArch-Hidden[[:space:]]*=/ { next }
        { print }
    ' "$dst" > "$tmp" && cat "$tmp" > "$dst"
    rm -f "$tmp"
}

if [[ "$act" == hide ]]; then
    marker=""
    if [[ ! -f "$dst" ]]; then
        src=$(find_src) || { echo "Desktop-Datei für '$id' nicht gefunden" >&2; exit 1; }
        cp "$src" "$dst"
        marker="X-sArch-Hidden=copy"            # Kopie stammt von uns -> beim Einblenden löschen
    elif grep -q '^X-sArch-Hidden=copy' "$dst"; then
        marker="X-sArch-Hidden=copy"
    fi
    rewrite hide "$marker"
    grep -qxF "$id" "$list" || echo "$id" >> "$list"
else
    if [[ -f "$dst" ]]; then
        if grep -q '^X-sArch-Hidden=copy' "$dst"; then
            rm -f "$dst"                        # unsere Kopie -> Systemdatei gilt wieder
        else
            rewrite show ""                     # eigene Datei des Benutzers: nur NoDisplay entfernen
        fi
    fi
    tmp=$(mktemp) && grep -vxF "$id" "$list" > "$tmp"; cat "$tmp" > "$list"; rm -f "$tmp"
fi
command -v update-desktop-database >/dev/null && update-desktop-database "$user_dir" &>/dev/null
exit 0
