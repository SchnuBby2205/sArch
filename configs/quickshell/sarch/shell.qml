// sArch Shell – Bar, Einstellungen, App-Launcher und Powermenü
//   (Frontend für bin/Settings/settings_backend.py, Bar-Konfiguration: bar.json)
//
//   Starten (Daemon):  qs -c sarch -n -d          (Autostart: bin/sarch_shell.sh)
//   Einstellungen:     qs -c sarch ipc call settings toggle ""   | open wallpaper | close
//   App-Launcher:      qs -c sarch ipc call launcher toggle      | open | close
//   Powermenü:         qs -c sarch ipc call power toggle         | open | close
//   Benachrichtigungen: qs -c sarch ipc call notifications toggle | dnd | clear
//   Bequemer:          bin/sarch_settings.sh [seite], bin/sarch_launcher.sh, bin/sarch_power.sh

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules
import qs.modules.bar
import qs.modules.notifications
import qs.services

ShellRoot {
    id: shell

    property bool shown: false              // Einstellungen
    property bool launcherShown: false
    property bool powerShown: false
    property bool notifShown: false          // Benachrichtigungszentrale
    property var notifScreen: Quickshell.screens[0]
    property var targetScreen: Quickshell.screens[0]

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        for (const s of Quickshell.screens)
            if (s.name === name)
                return s;
        return Quickshell.screens[0];
    }

    // immer nur ein Overlay gleichzeitig
    function closeOthers(keep) {
        if (keep !== "settings" && shown && ui.open)
            ui.requestClose(true);
        if (keep !== "launcher" && launcherShown)
            launcher.requestClose();
        if (keep !== "power" && powerShown)
            power.requestClose();
        if (keep !== "notifications" && notifShown)
            center.requestClose();
    }

    function open(page) {
        closeOthers("settings");
        if (!shown)
            targetScreen = focusedScreen();
        shown = true;
        Qt.callLater(() => ui.show(page));
    }
    function toggleSettings(page) {
        if (shown && ui.open && (page === "" || Backend.resolvePage(page) === Ui.current))
            ui.requestClose(false);
        else
            open(page);
    }

    function openLauncher() {
        closeOthers("launcher");
        if (!launcherShown)
            targetScreen = focusedScreen();
        launcherShown = true;
        Qt.callLater(() => launcher.show());
    }
    function toggleLauncher() {
        if (launcherShown && launcher.open)
            launcher.requestClose();
        else
            openLauncher();
    }

    function openPower() {
        closeOthers("power");
        if (!powerShown)
            targetScreen = focusedScreen();
        powerShown = true;
        Qt.callLater(() => power.show());
    }
    function togglePower() {
        if (powerShown && power.open)
            power.requestClose();
        else
            openPower();
    }

    function toggleNotifications() {
        if (notifShown && center.open) {
            center.requestClose();
            return;
        }
        closeOthers("notifications");
        if (!notifShown)
            targetScreen = focusedScreen();
        notifShown = true;
        Qt.callLater(() => center.show());
    }

    // ── Bar auf jedem Bildschirm ──
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // Icons in der Bar öffnen die Overlays direkt
    Connections {
        target: Ui
        function onOpenRequested(page) {
            shell.toggleSettings(page);
        }
        function onLauncherRequested() {
            shell.toggleLauncher();
        }
        function onPowerRequested() {
            shell.togglePower();
        }
    }

    Connections {
        target: Notifs
        function onCenterRequested() {
            shell.toggleNotifications();
        }
    }
    // Popups erscheinen auf dem Monitor, auf dem gerade gearbeitet wird
    Connections {
        target: Notifs.popupModel
        function onCountChanged() {
            if (Notifs.popupModel.count === 1)
                shell.notifScreen = shell.focusedScreen();
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            shell.toggleNotifications();
        }
        function dnd(): void {
            Notifs.setDnd(!Notifs.dnd);
        }
        function clear(): void {
            Notifs.clearPopups();
        }
    }

    IpcHandler {
        target: "settings"

        function open(page: string): void {
            shell.open(page);
        }
        function toggle(page: string): void {
            shell.toggleSettings(page);
        }
        function close(): void {
            if (shell.shown)
                ui.requestClose(true);
        }
    }

    IpcHandler {
        target: "launcher"

        function open(): void {
            shell.openLauncher();
        }
        function toggle(): void {
            shell.toggleLauncher();
        }
        function close(): void {
            if (shell.launcherShown)
                launcher.requestClose();
        }
    }

    IpcHandler {
        target: "power"

        function open(): void {
            shell.openPower();
        }
        function toggle(): void {
            shell.togglePower();
        }
        function close(): void {
            if (shell.powerShown)
                power.requestClose();
        }
    }

    // ── Einstellungen ──
    PanelWindow {
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

    // ── App-Launcher ──
    PanelWindow {
        visible: shell.launcherShown
        screen: shell.targetScreen
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        WlrLayershell.namespace: "sarch-launcher"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shell.launcherShown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Launcher {
            id: launcher

            anchors.fill: parent
            onOpenChanged: Ui.launcherOpen = open
            onClosed: shell.launcherShown = false
        }
    }

    // ── Powermenü ──
    PanelWindow {
        visible: shell.powerShown
        screen: shell.targetScreen
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        WlrLayershell.namespace: "sarch-power"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shell.powerShown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        PowerMenu {
            id: power

            anchors.fill: parent
            onOpenChanged: Ui.powerOpen = open
            onClosed: shell.powerShown = false
        }
    }

    // ── Benachrichtigungen: Popups ──
    // Position aus den Einstellungen (Leiste → Benachrichtigungen): top|middle|bottom - left|center|right
    PanelWindow {
        id: popupWin

        readonly property string pos: BarConfig.current.notifications?.position ?? "top-right"
        visible: Notifs.popupModel.count > 0
        screen: shell.notifScreen
        color: "transparent"
        anchors {
            top: pos.startsWith("top")
            bottom: pos.startsWith("bottom")
            left: pos.endsWith("left")
            right: pos.endsWith("right")
        }
        implicitWidth: popups.implicitWidth
        implicitHeight: popups.implicitHeight
        exclusiveZone: 0
        WlrLayershell.namespace: "sarch-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        NotifPopups {
            id: popups

            anchors.fill: parent
            position: popupWin.pos
        }
    }

    // ── Benachrichtigungszentrale ──
    PanelWindow {
        visible: shell.notifShown
        screen: shell.targetScreen
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusiveZone: 0
        WlrLayershell.namespace: "sarch-notification-center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shell.notifShown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        NotifCenter {
            id: center

            anchors.fill: parent
            onClosed: shell.notifShown = false
        }
    }
}
