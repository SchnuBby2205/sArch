pragma Singleton

import QtQuick
import Quickshell

// Globaler UI-Zustand: Navigation, Toasts, Dialoge, ungespeicherte Änderungen.
Singleton {
    id: root

    property string current: ""          // aktuelle Kategorie
    property string search: ""           // Suchtext der Sidebar
    property Item dialogHost: null        // wird von SettingsRoot gesetzt
    property bool busy: false

    // aktive Seite meldet hier ihre offenen Änderungen
    property int pendingCount: 0
    property var applyHandler: null
    property var resetHandler: null

    signal navigated(string name)
    signal openRequested(string page)   // Bar -> Einstellungsfenster öffnen
    signal powerRequested               // Bar -> Powermenü
    signal launcherRequested            // Bar -> App-Launcher
    property bool launcherOpen: false
    property bool powerOpen: false
    signal requestApply
    signal requestReset

    function navigate(name, force) {
        if (!name || name === current)
            return;
        if (!force && pendingCount > 0) {
            confirm({
                title: Backend.t("qs_discard_heading", "Änderungen verwerfen?"),
                body: Backend.t("qs_discard_body", "Auf dieser Seite gibt es {n} nicht übernommene Änderungen.", { n: pendingCount }),
                ok: Backend.t("qs_discard", "Verwerfen"),
                danger: true,
                icon: "edit_off"
            }, () => navigate(name, true));
            return;
        }
        current = name;
        navigated(name);
    }

    // ── Toasts ──
    readonly property ListModel toasts: ListModel {}
    property int _toastId: 0

    function toast(text, icon, kind) {
        _toastId += 1;
        toasts.append({
            tid: _toastId,
            text: text,
            icon: icon || "check_circle",
            kind: kind || "info"
        });
        if (toasts.count > 4)
            toasts.remove(0);
    }
    function dropToast(tid) {
        for (let i = 0; i < toasts.count; i++)
            if (toasts.get(i).tid === tid) {
                toasts.remove(i);
                return;
            }
    }

    // ── Dialoge (Implementierung in components/DialogHost.qml) ──
    function confirm(opts, cb) {
        if (dialogHost)
            dialogHost.openConfirm(opts, cb);
    }
    function form(opts, cb) {
        if (dialogHost)
            dialogHost.openForm(opts, cb);
    }
    function error(title, lines) {
        if (dialogHost)
            dialogHost.openError(title, lines);
    }
}
