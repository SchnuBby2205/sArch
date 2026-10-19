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
    readonly property string lang: Quickshell.env("SARCH_SETTINGS_LANG") || "de"

    property var categories: []
    property var strings: ({})
    property bool loading: false
    property bool loaded: false
    property string lastError: ""

    signal reloaded

    // Übersetzung mit Fallback + {platzhalter}
    function t(key, fallback, params) {
        let s = (strings && strings[key]) ? strings[key] : (fallback !== undefined ? fallback : key);
        if (params)
            for (const k in params)
                s = s.split(`{${k}}`).join(params[k]);
        return s;
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
                categories = res.categories || [];
                if (res.wallpaper && res.wallpaper.current)
                    Theme.wallpaper = res.wallpaper.current;
                loaded = true;
                lastError = "";
                root.reloaded();
            } else {
                lastError = res.error || "Backend-Fehler";
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
