pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Benachrichtigungen (ersetzt Dunst, solange Quickshell läuft – ohne Quickshell übernimmt Dunst wieder):
//  - popupModel:   gerade sichtbare Popups (Notification-Objekte über obj(nid))
//  - historyModel: Verlauf für die Benachrichtigungszentrale (wird in ~/.cache/sArch gespeichert)
Singleton {
    id: root

    property bool dnd: false              // Nicht stören: keine Popups (außer kritische)
    property int unread: 0                // neu seit dem letzten Öffnen der Zentrale
    property bool centerOpen: false
    signal centerRequested

    readonly property ListModel popupModel: ListModel {}
    readonly property ListModel historyModel: ListModel {}
    readonly property int maxHistory: 60
    readonly property int maxPopups: 5

    property var _objs: ({})
    function obj(nid) {
        return _objs[nid] ?? null;
    }

    // ── Hilfen ───────────────────────────────────────────────────────────────
    function hint(n, key) {
        const h = n?.hints;
        return h && h[key] !== undefined ? h[key] : undefined;
    }
    function stackTag(n) {
        return hint(n, "x-dunst-stack-tag") ?? hint(n, "x-canonical-private-synchronous") ?? "";
    }
    // Fortschritt 0..100 (dunstify -h int:value:42), sonst -1
    function progress(n) {
        const v = hint(n, "value");
        return v === undefined || v === null || isNaN(Number(v)) ? -1 : Math.max(0, Math.min(100, Number(v)));
    }
    // Anzeigedauer in ms; 0 = bleibt stehen
    function timeoutMs(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 0;
        let t = Number(n.expireTimeout);
        if (t > 0 && t < 100)
            t *= 1000;                           // Sekunden -> ms
        if (!(t > 0))
            t = n.urgency === NotificationUrgency.Low ? 4000 : 6500;
        return Math.min(t, 30000);
    }
    // Bildquelle für Icon/Bild der Benachrichtigung
    function iconSource(name) {
        if (!name)
            return "";
        if (name.startsWith("/"))
            return "file://" + name;
        if (name.startsWith("file://") || name.startsWith("image://") || name.startsWith("http"))
            return name;
        return Quickshell.iconPath(name, true) || "";
    }
    // Material-Symbol, wenn es kein Bild gibt
    function symbolFor(app, summary, prog) {
        const s = `${app} ${summary}`.toLowerCase();
        if (prog >= 0 && /vol|audio|media|sound|ton/.test(s))
            return "volume_up";
        if (/bright|hellig/.test(s))
            return "light_mode";
        if (/wallpaper|hintergrund|theme/.test(s))
            return "wallpaper";
        if (/screenshot|bildschirmfoto/.test(s))
            return "screenshot_monitor";
        if (/akku|battery/.test(s))
            return "battery_alert";
        if (/update|paket|pacman/.test(s))
            return "system_update";
        return "notifications";
    }
    // Text für die Zeitangabe
    function ago(ms, now) {
        const d = Math.max(0, (now - ms) / 1000);
        if (d < 60)
            return Backend.tr("jetzt");
        if (d < 3600)
            return Backend.tr("vor {n} Min.", { n: Math.floor(d / 60) });
        const t = new Date(ms), n = new Date(now);
        const hm = Qt.formatTime(t, "hh:mm");
        if (t.toDateString() === n.toDateString())
            return hm;
        const y = new Date(now - 86400000);
        if (t.toDateString() === y.toDateString())
            return Backend.tr("gestern {t}", { t: hm });
        return Qt.formatDateTime(t, Backend.german ? "dd.MM. hh:mm" : "MMM d, hh:mm");
    }

    // ── Server ───────────────────────────────────────────────────────────────
    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => root._add(n)
    }

    function _add(n) {
        n.tracked = true;
        const tag = stackTag(n);
        const nid = n.id;

        // gleicher Stack-Tag (z. B. Lautstärke): altes Popup ersetzen
        if (tag !== "") {
            for (let i = popupModel.count - 1; i >= 0; i--) {
                const o = obj(popupModel.get(i).nid);
                if (o && o !== n && stackTag(o) === tag)
                    o.dismiss();
            }
        }

        _objs[nid] = n;
        n.closed.connect(() => _removePopup(nid));

        // Verlauf: OSD-artige Meldungen (Fortschritt/transient) nicht aufheben
        const keep = !n.transient && progress(n) < 0;
        if (keep) {
            _addHistory(n);
            if (!centerOpen)
                unread += 1;
        }

        const show = !dnd || n.urgency === NotificationUrgency.Critical;
        let exists = false;
        for (let i = 0; i < popupModel.count; i++)
            if (popupModel.get(i).nid === nid)
                exists = true;
        if (show && !exists) {
            popupModel.insert(0, { nid: nid });
            while (popupModel.count > maxPopups) {
                const old = obj(popupModel.get(popupModel.count - 1).nid);
                popupModel.remove(popupModel.count - 1);
                old?.expire();
            }
        } else if (!show && !keep) {
            n.expire();
        }
    }

    function _removePopup(nid) {
        for (let i = 0; i < popupModel.count; i++)
            if (popupModel.get(i).nid === nid) {
                popupModel.remove(i);
                break;
            }
        delete _objs[nid];
    }

    function _addHistory(n) {
        // ersetzt (gleiche ID) -> Eintrag aktualisieren statt doppeln
        for (let i = 0; i < historyModel.count; i++)
            if (historyModel.get(i).nid === n.id && historyModel.get(i).fresh) {
                historyModel.remove(i);
                break;
            }
        const img = n.image || "";
        historyModel.insert(0, {
            nid: n.id,
            fresh: true,                       // stammt aus dieser Sitzung
            app: n.appName || "",
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body: n.body || "",
            image: img.startsWith("/") || img.startsWith("file://") ? img : "",
            urgency: Number(n.urgency),
            time: Date.now()
        });
        while (historyModel.count > maxHistory)
            historyModel.remove(historyModel.count - 1);
        saveTimer.restart();
    }

    // ── Aktionen für die Oberfläche ─────────────────────────────────────────
    function dismissPopup(nid) {
        obj(nid)?.dismiss();
    }
    function expirePopup(nid) {
        obj(nid)?.expire();
    }
    function invoke(nid, actionId) {
        const n = obj(nid);
        if (!n)
            return;
        const a = (n.actions || []).find(x => x.identifier === actionId);
        if (a)
            a.invoke();
        if (!n.resident)
            n.dismiss();
    }
    // Klick auf die Karte: Standard-Aktion, sonst schließen
    function activate(nid) {
        const n = obj(nid);
        if (!n)
            return;
        const def = (n.actions || []).find(x => x.identifier === "default");
        if (def)
            def.invoke();
        n.dismiss();
    }
    function removeHistory(index) {
        if (index >= 0 && index < historyModel.count) {
            historyModel.remove(index);
            saveTimer.restart();
        }
    }
    function clearHistory() {
        historyModel.clear();
        unread = 0;
        saveTimer.restart();
    }
    function clearPopups() {
        for (let i = popupModel.count - 1; i >= 0; i--)
            obj(popupModel.get(i).nid)?.dismiss();
    }
    function setDnd(on) {
        dnd = on;
        if (on)
            clearPopups();
        saveTimer.restart();
    }
    onCenterOpenChanged: if (centerOpen)
        unread = 0

    // ── Speichern / Laden ───────────────────────────────────────────────────
    readonly property string statePath: `${Quickshell.env("HOME")}/.cache/sArch/notifications.json`

    Timer {
        id: saveTimer

        interval: 600
        onTriggered: {
            const items = [];
            for (let i = 0; i < root.historyModel.count; i++) {
                const e = root.historyModel.get(i);
                items.push({ app: e.app, appIcon: e.appIcon, summary: e.summary, body: e.body, image: e.image, urgency: e.urgency, time: e.time });
            }
            stateFile.setText(JSON.stringify({ dnd: root.dnd, unread: root.unread, history: items }));
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.dnd = !!s.dnd;
                root.unread = Number(s.unread) || 0;
                for (const e of (s.history || []).slice(0, root.maxHistory))
                    root.historyModel.append({ nid: -1, fresh: false, app: e.app || "", appIcon: e.appIcon || "", summary: e.summary || "", body: e.body || "", image: e.image || "", urgency: Number(e.urgency) || 1, time: Number(e.time) || Date.now() });
            } catch (e) {}
        }
    }
}
