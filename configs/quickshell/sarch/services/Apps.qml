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

    // ausgeblendete Apps (bin/sarch_app_hide.sh): IDs aus ~/.config/sArch/hidden-apps
    readonly property string hideScript: `${Quickshell.env("HOME")}/.config/sArch/bin/sarch_app_hide.sh`
    property var hiddenIds: ({})
    function idOf(e) {
        return String(e?.id || "").replace(/\.desktop$/, "");
    }
    function isHidden(e) {
        return !!hiddenIds[idOf(e)];
    }

    readonly property var all: {
        const out = [];
        const seen = {};
        for (const e of (DesktopEntries.applications?.values ?? [])) {
            if (!e || e.noDisplay || !e.name || root.isHidden(e))
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

    // von uns ausgeblendete Apps (sind jetzt NoDisplay) – im Launcher mit "!" am Anfang der Suche
    readonly property var hidden: {
        const out = [];
        const seen = {};
        for (const e of (DesktopEntries.applications?.values ?? [])) {
            if (!e || !e.name || !root.isHidden(e) || seen[root.idOf(e)])
                continue;
            seen[root.idOf(e)] = true;
            out.push(e);
        }
        out.sort((a, b) => a.name.localeCompare(b.name, "de"));
        return out;
    }
    function hide(e) {
        const id = idOf(e);
        if (id === "")
            return;
        const h = Object.assign({}, hiddenIds);
        h[id] = true;
        hiddenIds = h;                         // sofort aus der Liste, die Datei folgt
        Quickshell.execDetached([hideScript, "hide", id]);
    }
    function unhide(e) {
        const id = idOf(e);
        const h = Object.assign({}, hiddenIds);
        delete h[id];
        hiddenIds = h;
        Quickshell.execDetached([hideScript, "show", id]);
    }

    function search(query) {
        if (query.trim().startsWith("!")) {
            const hq = query.trim().slice(1).trim().toLowerCase();
            return hq === "" ? hidden : hidden.filter(e => (e.name || "").toLowerCase().includes(hq));
        }
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
        // Terminal-Programme (Terminal=true, z. B. yazi, nvim, btop) brauchen ein Terminal –
        // execute() würde sie ohne starten, dann beenden sie sich sofort
        if (e.runInTerminal) {
            const term = Quickshell.env("TERMINAL") || "kitty";
            let cmd = (e.command || []).filter(a => !/^%[fFuUdDnNickvm]$/.test(a));
            if (cmd.length === 0)
                cmd = ["sh", "-c", String(e.execString || "").replace(/%[fFuUdDnNickvm]/g, "").trim()];
            const args = [term, "-e", ...cmd];
            if (e.workingDirectory)
                Quickshell.execDetached({ command: args, workingDirectory: e.workingDirectory });
            else
                Quickshell.execDetached(args);
            return;
        }
        e.execute();
    }

    FileView {
        id: hiddenFile

        path: `${Quickshell.env("HOME")}/.config/sArch/hidden-apps`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const h = {};
            for (const l of text().split("\n"))
                if (l.trim() !== "")
                    h[l.trim()] = true;
            root.hiddenIds = h;
        }
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
