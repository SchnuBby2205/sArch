pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Brücke zum Python-Backend (bin/Settings/settings_backend.py).
// Jeder Aufruf startet einen kurzen Prozess, der genau ein JSON-Objekt liefert.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string settingsDir: Quickshell.env("SARCH_SETTINGS_DIR") || `${home}/.config/sArch/bin/Settings`
    readonly property string backend: `${settingsDir}/settings_backend.py`
    readonly property string ini: Quickshell.env("SARCH_SETTINGS_INI") || `${settingsDir}/settings_de.ini`
    // Sprache: SARCH_SETTINGS_LANG, sonst Systemsprache (LC_ALL / LC_MESSAGES / LANG).
    // Quelltexte sind deutsch; für andere Sprachen übersetzt i18n/<lang>.json (Fallback: en.json).
    readonly property string lang: {
        const forced = (Quickshell.env("SARCH_SETTINGS_LANG") || "").trim().toLowerCase();
        if (forced !== "")
            return forced.slice(0, 2);
        for (const v of ["LC_ALL", "LC_MESSAGES", "LANG"]) {
            const l = (Quickshell.env(v) || "").trim();
            if (l === "")
                continue;
            if (l === "C" || l.startsWith("C.") || l === "POSIX")
                return "en";
            return l.slice(0, 2).toLowerCase();
        }
        return "de";
    }
    readonly property bool german: lang === "de"
    // Gebietsschema für Datum/Uhrzeit (Qt.locale)
    readonly property string locale: german ? "de_DE" : "en_US"
    property var dict: ({})

    property var categories: []
    property var strings: ({})
    property bool loading: false
    property bool loaded: false
    property string lastError: ""

    signal reloaded

    // Übersetzung mit Fallback + {platzhalter}
    function t(key, fallback, params) {
        let s;
        if (strings && strings[key])
            s = strings[key];
        else
            s = fallback !== undefined ? tr(fallback) : key;
        return fill(s, params);
    }
    // deutschen Quelltext übersetzen (Deutsch: unverändert)
    function tr(text, params) {
        const d = dict;                      // Abhängigkeit für Bindings
        let s = text === undefined || text === null ? "" : String(text);
        if (!german && s !== "" && d[s] !== undefined)
            s = d[s];
        return fill(s, params);
    }
    function fill(s, params) {
        if (params)
            for (const k in params)
                s = s.split(`{${k}}`).join(params[k]);
        return s;
    }
    // Anzeige-Texte des Backend-Modells (INI-Labels, Beschreibungen) übersetzen
    function translateModel(cats) {
        for (const c of cats) {
            c.title = tr(c.name);
            for (const g of (c.groups || [])) {
                g.title = tr(g.title);
                g.description = tr(g.description);
                for (const it of (g.items || [])) {
                    if (it.label !== undefined)
                        it.label = tr(it.label);
                    if (it.description !== undefined)
                        it.description = tr(it.description);
                    if (it.kind === "record" && it.title !== undefined)
                        it.title = tr(it.title);
                    for (const f of (it.fields || []))
                        f.label = tr(f.label);
                }
            }
        }
        return cats;
    }

    FileView {
        id: dictFile

        path: root.german ? "" : `${Quickshell.shellDir}/i18n/${root.lang}.json`
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                root.dict = JSON.parse(text()) || {};
            } catch (e) {
                root.dict = {};
            }
        }
        onLoadFailed: if (root.lang !== "en")
            path = `${Quickshell.shellDir}/i18n/en.json`
    }

    function category(name) {
        for (const c of categories)
            if (c.name === name)
                return c;
        return null;
    }

    // Seite per Kategoriename oder INI-Sektion finden (z.B. "wallpaper")
    function resolvePage(page) {
        if (!page)
            return "";
        const p = page.toLowerCase();
        for (const c of categories) {
            if (c.name.toLowerCase() === p)
                return c.name;
            for (const s of c.sections)
                if (s.toLowerCase() === p)
                    return c.name;
        }
        return "";
    }

    function reload(cb) {
        loading = true;
        call(["model"], res => {
            loading = false;
            if (res.ok) {
                strings = res.strings || {};
                categories = translateModel(res.categories || []);
                if (res.wallpaper && res.wallpaper.current)
                    Theme.wallpaper = res.wallpaper.current;
                loaded = true;
                lastError = "";
                root.reloaded();
            } else {
                lastError = res.error || tr("Backend-Fehler");
            }
            if (cb)
                cb(res);
        });
    }

    function call(args, cb) {
        const proc = procComponent.createObject(root, {
            command: ["python3", root.backend, root.ini, "--lang", root.lang].concat(args),
            callback: cb || null
        });
        proc.running = true;
    }

    function json(obj) {
        return JSON.stringify(obj);
    }

    Component {
        id: procComponent

        Process {
            id: proc

            property var callback: null

            stdout: StdioCollector {
                id: out
            }
            stderr: StdioCollector {
                id: err
            }

            // Collector-Text erst im nächsten Tick lesen (Streams sind dann sicher fertig)
            onExited: (exitCode, exitStatus) => Qt.callLater(() => proc.finish(exitCode))

            function finish(exitCode) {
                let res;
                try {
                    const txt = out.text.trim();
                    res = JSON.parse(txt.slice(txt.lastIndexOf("\n{") + 1));
                } catch (e) {
                    res = {
                        ok: false,
                        error: `Backend (${exitCode}): ${(err.text || out.text || String(e)).trim().slice(-400)}`,
                        errors: [(err.text || String(e)).trim().slice(-400)]
                    };
                    console.warn("sarch-settings:", res.error);
                }
                if (proc.callback)
                    proc.callback(res);
                proc.destroy();
            }
        }
    }
}
