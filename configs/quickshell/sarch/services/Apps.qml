pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Apps für den Launcher: Desktop-Einträge + Suche + "zuletzt/oft benutzt" (Frecency)
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("HOME")}/.cache/sArch/launcher.json`

    // { id: { count, last } }
    property var usage: ({})

    readonly property var all: {
        const out = [];
        const seen = {};
        for (const e of (DesktopEntries.applications?.values ?? [])) {
            if (!e || e.noDisplay || !e.name)
                continue;
            const key = e.id || e.name;
            if (seen[key])
                continue;
            seen[key] = true;
            out.push(e);
        }
        out.sort((a, b) => a.name.localeCompare(b.name, "de"));
        return out;
    }

    function keyOf(e) {
        return e.id || e.name;
    }

    function frecency(e) {
        const u = usage[keyOf(e)];
        if (!u)
            return 0;
        const ageH = (Date.now() - u.last) / 3600000;
        const recency = ageH < 4 ? 4 : ageH < 24 ? 2.5 : ageH < 168 ? 1.5 : 1;
        return u.count * recency;
    }

    readonly property var recent: {
        usage;
        return all.filter(e => usage[keyOf(e)]).sort((a, b) => frecency(b) - frecency(a)).slice(0, 6);
    }

    function score(e, q) {
        const name = (e.name || "").toLowerCase();
        let s = 0;
        if (name === q)
            s = 1000;
        else if (name.startsWith(q))
            s = 800;
        else if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            s = 600;
        else if (name.includes(q))
            s = 450;
        else {
            const hay = [e.genericName, e.comment, (e.keywords || []).join(" "), (e.categories || []).join(" "), e.id]
                .join(" ").toLowerCase();
            if (hay.includes(q))
                s = 250;
            else {
                // Buchstaben in Reihenfolge (z.B. "ffx" -> Firefox)
                let i = 0;
                for (const ch of name)
                    if (ch === q[i])
                        i++;
                if (i === q.length)
                    s = 120 - (name.length - q.length);
            }
        }
        return s > 0 ? s + Math.min(150, frecency(e) * 10) : 0;
    }

    function search(query) {
        const q = query.trim().toLowerCase();
        if (q === "")
            return all;
        return all.map(e => ({ e: e, s: score(e, q) })).filter(x => x.s > 0).sort((a, b) => b.s - a.s).map(x => x.e);
    }

    function launch(e) {
        const k = keyOf(e);
        const u = Object.assign({}, usage);
        u[k] = { count: (u[k]?.count ?? 0) + 1, last: Date.now() };
        usage = u;
        store.setText(JSON.stringify(u));
        e.execute();
    }

    FileView {
        id: store

        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                root.usage = JSON.parse(text()) || {};
            } catch (e) {
                root.usage = {};
            }
        }
    }
}
