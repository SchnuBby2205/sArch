# sarch (Quickshell): Bar + Einstellungen

Quickshell-Shell für sArch: eine **Bar** auf jedem Bildschirm und die
**Einstellungen** als Overlay – beides im selben Prozess.

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
configs/quickshell/sarch/
  shell.qml             Bar je Bildschirm + Einstellungsfenster + IPC
  bar.json              Konfiguration der Bar
  services/             Theme (matugen-Farben), Backend, Ui-Zustand
  components/           Buttons, Slider, Felder, Dialoge, Toasts …
  modules/              Sidebar, Seiten, Wallpaper-Karussell, Schriften, Leiste
  modules/bar/          Bar und ihre Module
```

## Bar

Konfiguriert wird sie in den Einstellungen unter **Leiste** (Live-Vorschau –
einfach die gewünschte Bildschirmkante anklicken). Gespeichert wird in
`bar.json` in diesem Ordner, die Bar übernimmt Änderungen sofort.

- Position: oben, unten, links, rechts (Bar fährt animiert an die neue Kante)
- Stil: `islands` (jede Zone eine Pille), `floating`, `docked`
- Größe, Abstand, Rundung, Deckkraft
- Module je Zone (start / center / end bzw. links-mitte-rechts / oben-mitte-unten)
  in beliebiger Reihenfolge: Workspaces, Uhrzeit, Datum, Hintergrundbild,
  Einstellungen, Audio (Klick pavucontrol, Mausrad Lautstärke, Mitte stumm),
  Power-Menü (`bin/sarch_powermenu.sh`)

## App-Launcher & Powermenü

- **App-Launcher** (SUPER+A oder Bar-Icon): tippen sucht sofort (Name, Beschreibung,
  Stichworte, Buchstabenfolge wie „ffx“), Pfeile wählen, Enter startet.
  Oft/zuletzt benutzte Apps stehen oben (`~/.cache/sArch/launcher.json`).
- **Powermenü** (SUPER+Backspace oder Bar-Icon): Sperren, Bereitschaft, Ruhezustand,
  Abmelden, Neustart, Herunterfahren. Abmelden/Neustart/Herunterfahren starten einen
  Countdown-Ring – nochmal drücken = sofort, Esc bricht ab. Buchstaben L/S/H/E/R/P
  wählen direkt. Ausgeführt wird über `bin/sarch_power_action.sh` (Sperren: hyprlock).
- Ist Quickshell deaktiviert, öffnen `sarch_launcher.sh` / `sarch_power.sh` wieder Rofi.

## Benutzen

```sh
qs -c sarch -n -d                  # Daemon (steht in autostart.lua)
~/.config/sArch/bin/sarch_settings.sh       # öffnen / schließen (SUPER+ALT+S)
~/.config/sArch/bin/sarch_settings.sh wallpaper   # direkt zur Seite (SUPER+W)
qs -c sarch ipc call settings open Keybindings
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
| `SARCH_BAR_CONFIG`    | `<shell-ordner>/bar.json`                  |

## Kategorie-Icons

Pro INI-Sektion optional `icon = <material-symbol>` (z.B. `icon = keyboard`).
Ohne Angabe wird anhand von Kategoriename/Typ ein passendes Icon gewählt.
