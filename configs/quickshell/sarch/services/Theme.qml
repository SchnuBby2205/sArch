pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Farben (matugen → ~/.cache/sArch/qs-colors.json), Schriften, Radien, Animationskurven.
// Alle Farben animieren weich, wenn sich das Schema ändert (neues Wallpaper) oder eine
// Vorschau (Hover über Akzentfarbe) aktiv ist.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string colorsPath: Quickshell.env("SARCH_QS_COLORS") || `${home}/.cache/sArch/qs-colors.json`

    // ── Schema ───────────────────────────────────────────────────────────────
    property var scheme: ({})
    property var preview: null          // komplettes Schema als Vorschau
    property string previewAccent: ""   // Fallback, wenn matugen kein JSON liefert
    property string wallpaper: ""       // aktuelles Bild (Hintergrund der Maske)
    property string previewWallpaper: ""

    readonly property var defaults: ({
        primary: "#cdbdff", on_primary: "#35275f",
        primary_container: "#4c3e77", on_primary_container: "#e8ddff",
        secondary: "#cac3dc", on_secondary: "#322e41",
        secondary_container: "#494458", on_secondary_container: "#e7dff8",
        tertiary: "#eeb8c9", on_tertiary: "#4a2533",
        tertiary_container: "#643b49", on_tertiary_container: "#ffd9e3",
        error: "#ffb4ab", on_error: "#690005",
        error_container: "#93000a", on_error_container: "#ffdad6",
        surface: "#141218", on_surface: "#e6e0e9", on_surface_variant: "#cac4cf",
        outline: "#948f99", outline_variant: "#49454e",
        surface_container_lowest: "#0f0d13", surface_container_low: "#1d1b20",
        surface_container: "#211f24", surface_container_high: "#2b292f",
        surface_container_highest: "#36343a", shadow: "#000000", scrim: "#000000"
    })

    // Ziel-Palette (Vorschau > Akzent-Vorschau > matugen > Standard)
    readonly property var target: {
        const out = {};
        for (const k in defaults) {
            let v = scheme[k] || defaults[k];
            if (previewAccent !== "" && (k === "primary" || k === "tertiary"))
                v = previewAccent;
            if (preview && preview[k])
                v = preview[k];
            out[k] = v;
        }
        return out;
    }

    // Übergang: zwischen fromPal und toPal wird mit t (0..1) interpoliert.
    // (Behaviors auf Singleton-Properties sind nicht stabil -> eine Animation für alle Farben.)
    property var fromPal: ({})
    property var toPal: ({})
    property real t: 1

    onTargetChanged: {
        const cur = {};
        for (const k in defaults)
            cur[k] = toPal[k] ? mixHex(fromPal[k] || toPal[k], toPal[k], t) : target[k];
        fromPal = cur;
        toPal = target;
        t = 0;
        fade.restart();
    }

    function mixHex(a, b, f) {
        const x = Qt.color(a || "#000000");
        const y = Qt.color(b || "#000000");
        return Qt.rgba(x.r + (y.r - x.r) * f, x.g + (y.g - x.g) * f, x.b + (y.b - x.b) * f, 1);
    }
    function c(key) {
        if (!toPal[key])
            return target[key];
        return mixHex(fromPal[key] || toPal[key], toPal[key], t);
    }

    NumberAnimation {
        id: fade

        target: root
        property: "t"
        from: 0
        to: 1
        duration: root.colorDuration
        easing.type: Easing.OutCubic
    }

    property color primary: c("primary")
    property color primaryFg: c("on_primary")
    property color primaryContainer: c("primary_container")
    property color primaryContainerFg: c("on_primary_container")
    property color secondary: c("secondary")
    property color secondaryContainer: c("secondary_container")
    property color secondaryContainerFg: c("on_secondary_container")
    property color tertiary: c("tertiary")
    property color tertiaryContainer: c("tertiary_container")
    property color tertiaryContainerFg: c("on_tertiary_container")
    property color error: c("error")
    property color errorFg: c("on_error")
    property color errorContainer: c("error_container")
    property color errorContainerFg: c("on_error_container")
    property color surface: c("surface")
    property color surfaceFg: c("on_surface")
    property color surfaceFgDim: c("on_surface_variant")
    property color outline: c("outline")
    property color outlineVariant: c("outline_variant")
    property color surfaceLowest: c("surface_container_lowest")
    property color surfaceLow: c("surface_container_low")
    property color surfaceContainer: c("surface_container")
    property color surfaceHigh: c("surface_container_high")
    property color surfaceHighest: c("surface_container_highest")


    readonly property int colorDuration: 650

    function alpha(col, a) {
        return Qt.rgba(col.r, col.g, col.b, a);
    }
    function mix(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, a.a * (1 - t) + b.a * t);
    }
    function contrast(hex) {
        const col = Qt.color(hex);
        return (0.299 * col.r + 0.587 * col.g + 0.114 * col.b) > 0.55 ? "#1a1a1a" : "#ffffff";
    }

    // ── Schriften ────────────────────────────────────────────────────────────
    function pickFont(list) {
        const fams = Qt.fontFamilies();
        for (const f of list)
            if (fams.indexOf(f) >= 0)
                return f;
        return list[list.length - 1];
    }
    // Oberflächen-Schrift aus den Einstellungen (Schriften → Oberfläche) – dieselbe wie Rofi/Dunst
    property string uiFont: ""
    property real uiFontSize: 0            // Punktgröße aus den Einstellungen (0 = unbekannt)
    // Skalierung aller Schriftgrößen: Referenz ist 12 pt (Rofi/Dunst-Standard)
    readonly property real fontScale: uiFontSize > 0 ? Math.max(0.8, Math.min(1.5, uiFontSize / 12)) : 1
    function fs(px) {
        return Math.round(px * fontScale);
    }
    readonly property string fallbackSans: pickFont(["Rubik", "Google Sans", "Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "sans-serif"])
    readonly property string sans: uiFont !== "" && Qt.fontFamilies().indexOf(uiFont) >= 0 ? uiFont : fallbackSans
    readonly property string mono: pickFont(["JetBrainsMono Nerd Font", "JetBrainsMonoNL Nerd Font", "JetBrains Mono", "Iosevka Nerd Font", "DejaVu Sans Mono", "monospace"])
    readonly property string icons: "Material Symbols Rounded"

    readonly property QtObject size: QtObject {
        readonly property int tiny: root.fs(11)
        readonly property int small: root.fs(12)
        readonly property int body: root.fs(14)
        readonly property int label: root.fs(15)
        readonly property int title: root.fs(18)
        readonly property int headline: root.fs(26)
        readonly property int display: root.fs(40)
    }

    readonly property QtObject radius: QtObject {
        readonly property int small: 10
        readonly property int normal: 16
        readonly property int large: 22
        readonly property int xl: 30
        readonly property int full: 1000
    }

    // ── Animation (Material 3 Expressive) ────────────────────────────────────
    readonly property QtObject anim: QtObject {
        readonly property var curves: ({
            standard: [0.2, 0, 0, 1, 1, 1],
            decel: [0, 0, 0, 1, 1, 1],
            emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
            emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1],
            emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1],
            spatialFast: [0.42, 1.67, 0.21, 0.9, 1, 1],
            spatial: [0.38, 1.21, 0.22, 1, 1, 1],
            spatialSlow: [0.39, 1.29, 0.35, 0.98, 1, 1],
            effects: [0.34, 0.8, 0.34, 1, 1, 1]
        })
        readonly property var durations: ({
            standard: 300,
            decel: 300,
            emphasized: 500,
            emphasizedDecel: 400,
            emphasizedAccel: 200,
            spatialFast: 350,
            spatial: 500,
            spatialSlow: 650,
            effects: 200
        })
    }

    // ── Oberflächen-Schrift beobachten (rofi: mainfont: "Familie 12", dunst: font = "Familie 12") ──
    readonly property string rofiFontPath: Quickshell.env("SARCH_UI_FONT_FILE") || `${home}/.config/rofi/colors.rasi`
    readonly property string dunstFontPath: `${home}/.config/dunst/dunstrc`

    // "Familie 12" -> { family: "Familie", size: 12 }
    function fontFrom(txt, re) {
        const m = re.exec(txt || "");
        if (!m)
            return null;
        const spec = m[1].trim();
        const sm = /\s+(\d+(\.\d+)?)$/.exec(spec);
        return { family: sm ? spec.slice(0, sm.index).trim() : spec, size: sm ? parseFloat(sm[1]) : 0 };
    }
    function updateUiFont() {
        const f = fontFrom(rofiFont.text(), /^\s*mainfont:\s*"([^"]*)"/m) || fontFrom(dunstFont.text(), /^\s*font\s*=\s*"([^"]*)"/m);
        const fam = f?.family ?? "", size = f?.size ?? 0;
        if (fam !== uiFont)
            uiFont = fam;
        if (size !== uiFontSize)
            uiFontSize = size;
    }

    FileView {
        id: rofiFont

        path: root.rofiFontPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.updateUiFont()
    }
    FileView {
        id: dunstFont

        path: root.dunstFontPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.updateUiFont()
    }

    // ── matugen-Farben laden + live beobachten ───────────────────────────────
    // falls die Datei beim Start noch fehlte (erster matugen-Lauf), manuell nachladen
    function reloadColors() {
        colorsFile.reload();
    }

    FileView {
        id: colorsFile
        path: root.colorsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                delete parsed._end;
                root.scheme = parsed;
                // neues Schema ist da -> Vorschau (falls nach dem Anwenden noch gehalten) beenden
                root.preview = null;
                root.previewAccent = "";
            } catch (e) {
                console.warn("sarch-settings: colors.json ungültig:", e);
            }
        }
    }
}
