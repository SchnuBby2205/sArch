// sArch Shell – Bar + Einstellungen (Frontend für bin/Settings/settings_backend.py)
//   Bar-Konfiguration: bar.json (wird über die Einstellungen → "Leiste" bearbeitet)
//
//   Starten (Daemon, bleibt im Hintergrund):  qs -c sarch -n -d
//   Öffnen:      qs -c sarch ipc call settings open ""          (letzte/erste Seite)
//                qs -c sarch ipc call settings open wallpaper   (Kategorie oder INI-Sektion)
//   Umschalten:  qs -c sarch ipc call settings toggle ""
//   Schließen:   qs -c sarch ipc call settings close
//   Bequemer:    ~/.config/sArch/bin/sarch_settings.sh [seite]

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules
import qs.modules.bar
import qs.services

ShellRoot {
    id: shell

    property bool shown: false
    property var targetScreen: Quickshell.screens[0]

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        for (const s of Quickshell.screens)
            if (s.name === name)
                return s;
        return Quickshell.screens[0];
    }

    function open(page) {
        if (!shown)
            targetScreen = focusedScreen();
        shown = true;
        Qt.callLater(() => ui.show(page));
    }

    // ── Bar auf jedem Bildschirm ──
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // Icons in der Bar öffnen das Einstellungsfenster direkt
    Connections {
        target: Ui
        function onOpenRequested(page) {
            if (shell.shown && ui.open && (page === "" || Backend.resolvePage(page) === Ui.current))
                ui.requestClose(false);
            else
                shell.open(page);
        }
    }

    IpcHandler {
        target: "settings"

        function open(page: string): void {
            shell.open(page);
        }
        function toggle(page: string): void {
            if (shell.shown && ui.open)
                ui.requestClose(false);
            else
                shell.open(page);
        }
        function close(): void {
            if (shell.shown)
                ui.requestClose(true);
        }
    }

    PanelWindow {
        id: win

        visible: shell.shown
        screen: shell.targetScreen
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "sarch-settings"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shell.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        SettingsRoot {
            id: ui

            anchors.fill: parent
            onClosed: shell.shown = false
        }
    }
}
