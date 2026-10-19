pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Konfiguration der Bar: bar.json (im Shell-Ordner) + Standardwerte.
// Die Einstellungs-App schreibt die Datei, die Bar übernimmt Änderungen sofort.
Singleton {
    id: root

    readonly property string path: Quickshell.env("SARCH_BAR_CONFIG") || `${Quickshell.shellDir}/bar.json`

    readonly property var defaults: ({
        position: "top",          // top | bottom | left | right
        style: "islands",         // islands | floating | docked
        size: 42,                 // Dicke der Bar in px
        margin: 8,                // Abstand zum Bildschirmrand (islands / floating)
        radius: 18,               // Eckenradius
        opacity: 0.86,            // Deckkraft des Hintergrunds
        clock: { seconds: false, h24: true },
        date: { format: "ddd, d. MMM" },
        workspaces: { count: 8, numbers: true },
        audio: { percent: true },
        modules: [
            { id: "workspaces", zone: "start" },
            { id: "clock", zone: "center" },
            { id: "date", zone: "center" },
            { id: "wallpaper", zone: "end" },
            { id: "settings", zone: "end" },
            { id: "audio", zone: "end" },
            { id: "power", zone: "end" }
        ]
    })

    // Katalog aller Module (Reihenfolge = Anzeige in den Einstellungen)
    readonly property var catalog: [
        { id: "workspaces", icon: "space_dashboard", label: "Workspaces", desc: "Workspace-Anzeige · Klick wechselt, Mausrad blättert" },
        { id: "clock", icon: "schedule", label: "Uhrzeit", desc: "Uhr mit rollenden Ziffern" },
        { id: "date", icon: "calendar_month", label: "Datum", desc: "Datum im frei wählbaren Format" },
        { id: "wallpaper", icon: "wallpaper", label: "Hintergrundbild", desc: "Öffnet die Wallpaper-Auswahl" },
        { id: "settings", icon: "settings", label: "Einstellungen", desc: "Öffnet die Einstellungen" },
        { id: "audio", icon: "volume_up", label: "Audio", desc: "Lautstärke · Klick: pavucontrol, Mausrad: lauter/leiser, Mitte: stumm" },
        { id: "power", icon: "power_settings_new", label: "Power-Menü", desc: "Öffnet das Power-Menü" }
    ]

    function info(id) {
        return catalog.find(c => c.id === id) || { id: id, icon: "extension", label: id, desc: "" };
    }

    property var loaded: ({})
    readonly property var current: merge(defaults, loaded)

    // tiefe Zusammenführung: Objekte werden gemischt, Arrays/Werte ersetzt
    function merge(base, over) {
        if (over === undefined || over === null)
            return JSON.parse(JSON.stringify(base));
        if (typeof base !== "object" || Array.isArray(base) || typeof over !== "object" || Array.isArray(over))
            return JSON.parse(JSON.stringify(over));
        const out = {};
        for (const k in base)
            out[k] = merge(base[k], over[k]);
        for (const k in over)
            if (!(k in base))
                out[k] = JSON.parse(JSON.stringify(over[k]));
        // unbekannte/doppelte Module aussortieren, fehlende als "off" anhängen
        if (out.modules) {
            const seen = {};
            out.modules = out.modules.filter(m => m && m.id && !seen[m.id] && (seen[m.id] = true));
            for (const c of root.catalog)
                if (!seen[c.id])
                    out.modules.push({ id: c.id, zone: "off" });
        }
        return out;
    }

    function reload() {
        file.reload();
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.loaded = JSON.parse(text());
            } catch (e) {
                console.warn("sarch bar: bar.json ungültig:", e);
            }
        }
    }
}
