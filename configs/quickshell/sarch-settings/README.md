# sarch-settings (Quickshell)

Quickshell-Oberfläche für die sArch-Einstellungen. Ersetzt die GTK-Maske
`bin/Settings/settings_mask.py` optisch – die Lese-/Schreiblogik für die
Hyprland-Lua-Configs ist unverändert und liegt jetzt in
`bin/Settings/settings_core.py`. Die Oberfläche spricht über
`bin/Settings/settings_backend.py` (JSON-CLI) mit ihr.

```
bin/Settings/
  settings_core.py      Logik (INI, Lua-Parser, Wallpaper, Fonts) – geteilt
  settings_backend.py   JSON-Backend für Quickshell
  settings_mask.py      alte GTK-Maske (Fallback, nutzt settings_core)
  settings_de.ini       Kategorien / Felder (unverändert gültig)
bin/sarch_settings.sh   öffnet die Oberfläche (startet den Daemon bei Bedarf)
configs/quickshell/sarch-settings/
  shell.qml             Layer-Shell-Fenster + IPC
  services/             Theme (matugen-Farben), Backend, Ui-Zustand
  components/           Buttons, Slider, Felder, Dialoge, Toasts …
  modules/              Sidebar, Seiten, Wallpaper-Karussell, Schriften
```

## Benutzen

```sh
qs -c sarch-settings -n -d                  # Daemon (steht in autostart.lua)
~/.config/sArch/bin/sarch_settings.sh       # öffnen / schließen (SUPER+ALT+S)
~/.config/sArch/bin/sarch_settings.sh wallpaper   # direkt zur Seite (SUPER+W)
qs -c sarch-settings ipc call settings open Keybindings
```

Tastatur: `Esc` schließen · `Strg+F` suchen · `Strg+S` übernehmen ·
`Strg+Z` zurücksetzen · `Strg+↑/↓` bzw. `Strg+Tab` Kategorie wechseln ·
`←/→` und `Enter` im Wallpaper-Karussell.

## Abhängigkeiten

`quickshell`, `python`, `matugen`, `imagemagick`, Schrift
`ttf-material-symbols-variable` (Icons). Optional für die Optik: `ttf-rubik`
oder `inter-font` (sonst Noto/DejaVu).

## Farben

matugen schreibt über das Template `matugen/templates/quickshell-colors.json`
nach `~/.cache/sArch/qs-colors.json`. Die Oberfläche beobachtet die Datei und
blendet neue Farben weich ein. Beim Hover über eine Akzentfarbe holt sie sich
per `matugen --dry-run --json hex` das komplette Schema als Live-Vorschau.

## Umgebungsvariablen (optional)

| Variable              | Standard                                   |
|-----------------------|--------------------------------------------|
| `SARCH_SETTINGS_DIR`  | `~/.config/sArch/bin/Settings`             |
| `SARCH_SETTINGS_INI`  | `$SARCH_SETTINGS_DIR/settings_de.ini`      |
| `SARCH_SETTINGS_LANG` | `de`                                       |
| `SARCH_QS_COLORS`     | `~/.cache/sArch/qs-colors.json`            |

## Kategorie-Icons

Pro INI-Sektion optional `icon = <material-symbol>` (z.B. `icon = keyboard`).
Ohne Angabe wird anhand von Kategoriename/Typ ein passendes Icon gewählt.
