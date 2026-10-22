pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper-Übergang (awww): ~/.config/sArch/wallpaper-transition.conf, gelesen von bin/sarch_wallpaper_set.sh
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string path: `${home}/.config/sArch/wallpaper-transition.conf`
    readonly property string setter: `${home}/.config/sArch/bin/sarch_wallpaper_set.sh`

    property string type: "random"
    property real duration: 1.6
    property string bezier: ".54,0,.34,.99"
    property bool cursor: true
    property bool closeSettings: false   // Einstellungen nach Wallpaper-Wahl schließen (Übergang sichtbar)

    // Effekte (Reihenfolge = Anzeige)
    readonly property var types: [
        { id: "random", icon: "shuffle", label: Backend.tr("Zufällig"), desc: Backend.tr("Jedes Mal ein anderer Effekt") },
        { id: "grow", icon: "radio_button_checked", label: Backend.tr("Kreis"), desc: Backend.tr("Öffnet sich als Kreis – am Mauszeiger") },
        { id: "outer", icon: "filter_tilt_shift", label: Backend.tr("Von außen"), desc: Backend.tr("Kreis schließt sich zum Mauszeiger hin") },
        { id: "wave", icon: "waves", label: Backend.tr("Welle"), desc: Backend.tr("Wellenkante in zufälligem Winkel") },
        { id: "wipe", icon: "swipe_right", label: Backend.tr("Wischen"), desc: Backend.tr("Gerade Kante in zufälligem Winkel") },
        { id: "slide", icon: "open_in_full", label: Backend.tr("Schieben"), desc: Backend.tr("Von einem zufälligen Rand") },
        { id: "slice", icon: "content_cut", label: Backend.tr("Zerschneiden"), desc: Backend.tr("Schräge Streifen fliegen nach rechts oben und links unten weg") },
        { id: "flip", icon: "grid_view", label: Backend.tr("Kacheln"), desc: Backend.tr("Kacheln klappen in einer Welle um") },
        { id: "center", icon: "center_focus_strong", label: Backend.tr("Mitte"), desc: Backend.tr("Kreis aus der Bildschirmmitte") },
        { id: "any", icon: "scatter_plot", label: Backend.tr("Irgendwo"), desc: Backend.tr("Kreis an einer zufälligen Stelle") },
        { id: "fade", icon: "gradient", label: Backend.tr("Überblenden"), desc: Backend.tr("Weiches Ineinanderblenden") },
        { id: "simple", icon: "crop_square", label: Backend.tr("Einfach"), desc: Backend.tr("Schlichtes Umschalten") }
    ]
    readonly property var curves: [
        { id: ".54,0,.34,.99", label: Backend.tr("Weich") },
        { id: ".05,.9,.1,1", label: Backend.tr("Schnell") },
        { id: ".34,1.4,.64,1", label: Backend.tr("Federnd") },
        { id: "0,0,1,1", label: Backend.tr("Linear") }
    ]

    function save() {
        file.setText(`TYPE=${type}\nDURATION=${duration.toFixed(1)}\nBEZIER=${bezier}\nCURSOR=${cursor}\nFPS=auto\nCLOSE=${closeSettings}\n`);
    }
    // Bild sofort mit dem Übergang setzen (ohne Umweg über das Python-Backend).
    // true = gestartet; das Backend wird danach mit "noset" nur noch für matugen & Co. aufgerufen.
    // zuletzt sichtbar gesetztes Bild (Theme.wallpaper folgt erst, wenn das Backend fertig ist)
    property string shown: ""
    function current() {
        return shown !== "" ? shown : Theme.wallpaper;
    }
    function setNow(path) {
        if (!path || path === current())
            return false;                  // gleiches Bild (nur andere Akzentfarbe): kein Übergang
        const old = current();
        shown = path;
        saveTimer.stop();
        save();                            // geänderte Einstellungen sicher übernehmen
        // Typ hier auswürfeln (wie bin/sarch_wallpaper_set.sh), damit Zerschneiden/Kacheln direkt
        // in Quickshell starten – ohne Umweg Skript -> "qs ipc call" (kostete eine spürbare Pause)
        let t = type;
        if (t === "random") {
            const pool = ["grow", "outer", "wave", "wipe", "center", "any", "fade", "slide", "slice", "flip", "slice", "flip"];
            t = pool[Math.floor(Math.random() * pool.length)];
        }
        if ((t === "slice" || t === "flip") && old !== "") {
            WallFxState.start(old, path, t, duration);
            return true;
        }
        Quickshell.execDetached(["env", `SARCH_WP_TYPE=${t}`, setter, path]);
        return true;
    }
    // Wallpaper übernehmen: Übergang sofort, danach das Backend (matugen, Farben, Vorschaubilder).
    // Backend-Aufrufe laufen nacheinander und nur der letzte Wunsch zählt – sonst konnte ein älterer,
    // langsamerer matugen-Lauf die gerade gewählte Akzentfarbe wieder überschreiben.
    // cb(res): res.superseded = durch eine neuere Auswahl ersetzt
    property bool applyBusy: false
    property var applyNext: null
    function applyWallpaper(path, idx, hex, cb) {
        const job = { path: path, idx: idx, hex: hex || "", noset: setNow(path), cb: cb || null };
        afterStart(() => queueApply(job));
    }
    function queueApply(job) {
        if (applyBusy) {
            if (applyNext) {
                job.noset = job.noset || (applyNext.noset && applyNext.path === job.path);
                if (applyNext.cb)
                    applyNext.cb({ ok: true, superseded: true });
            }
            applyNext = job;
            return;
        }
        runApply(job);
    }
    function runApply(job) {
        applyBusy = true;
        Backend.call(["set-wallpaper", job.path, String(job.idx), job.hex].concat(job.noset ? ["noset"] : []), res => {
            applyBusy = false;
            if (res.ok) {
                Theme.wallpaper = job.path;
                if (shown === job.path)
                    shown = "";
            }
            const next = applyNext;
            applyNext = null;
            if (job.cb)
                job.cb(next ? Object.assign({}, res, { superseded: true }) : res);
            if (next)
                runApply(next);
            else if (res.ok)
                Theme.reloadColors();
        });
    }

    // cb erst ausführen, wenn der Übergang läuft (matugen & Co. sollen ihm keine CPU wegnehmen)
    function afterStart(cb) {
        if (!WallFxState.preparing) {
            cb();
            return;
        }
        pendingCbs.push(cb);
    }
    property var pendingCbs: []
    Connections {
        target: WallFxState
        function onPreparingChanged() {
            if (WallFxState.preparing)
                return;
            const cbs = root.pendingCbs;
            root.pendingCbs = [];
            for (const cb of cbs)
                cb();
        }
    }
    function set(key, value) {
        root[key] = value;
        saveTimer.restart();
    }
    // aktuelles Wallpaper mit dem eingestellten Übergang neu setzen
    // Vorschau: erst auf eine abgedunkelte Version des Bildes, dann zurück – beide Male mit dem Effekt
    // (awww zeigt beim Setzen desselben Bildes keinen Übergang)
    function tryNow() {
        saveTimer.stop();
        save();
        tryTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: root.save()
    }
    Timer {
        id: tryTimer

        interval: 150      // Datei erst schreiben lassen
        onTriggered: Quickshell.execDetached([root.setter, "--try"])
    }

    FileView {
        id: file

        path: root.path
        printErrors: false
        onLoaded: {
            for (const line of text().split("\n")) {
                const i = line.indexOf("=");
                if (i < 0)
                    continue;
                const k = line.slice(0, i).trim(), v = line.slice(i + 1).trim();
                if (k === "TYPE" && v)
                    root.type = v;
                else if (k === "DURATION" && !isNaN(Number(v)))
                    root.duration = Number(v);
                else if (k === "BEZIER" && v)
                    root.bezier = v;
                else if (k === "CURSOR")
                    root.cursor = v !== "false";
                else if (k === "CLOSE")
                    root.closeSettings = v === "true";
            }
        }
    }
}
