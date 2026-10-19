import QtQuick
import Quickshell
import qs.services

// Lädt ein Bar-Modul anhand seiner ID
Loader {
    id: root

    property string moduleId: ""
    property var cfg
    property bool vertical: false
    property real thick: 40
    property var screen: null
    property bool preview: false

    readonly property string home: Quickshell.env("HOME") || ""

    sourceComponent: {
        switch (moduleId) {
        case "workspaces": return wsComp;
        case "clock": return clockComp;
        case "date": return dateComp;
        case "audio": return audioComp;
        case "wallpaper":
        case "settings":
        case "power": return buttonComp;
        }
        return null;
    }

    Component {
        id: wsComp
        BarWorkspaces { cfg: root.cfg; vertical: root.vertical; thick: root.thick; screen: root.screen }
    }
    Component {
        id: clockComp
        BarClock { cfg: root.cfg; vertical: root.vertical; thick: root.thick }
    }
    Component {
        id: dateComp
        BarDate { cfg: root.cfg; vertical: root.vertical; thick: root.thick }
    }
    Component {
        id: audioComp
        BarAudio { cfg: root.cfg; vertical: root.vertical; thick: root.thick }
    }
    Component {
        id: buttonComp
        BarButton {
            thick: root.thick
            vertical: root.vertical
            icon: BarConfig.info(root.moduleId).icon
            accent: root.moduleId === "power" ? Theme.error : root.moduleId === "wallpaper" ? Theme.tertiary : Theme.primary
            onClicked: {
                if (root.preview)
                    return;
                if (root.moduleId === "wallpaper")
                    Ui.openRequested("wallpaper");
                else if (root.moduleId === "settings")
                    Ui.openRequested("");
                else if (root.moduleId === "power")
                    Quickshell.execDetached([`${root.home}/.config/sArch/bin/sarch_powermenu.sh`]);
            }
        }
    }
}
