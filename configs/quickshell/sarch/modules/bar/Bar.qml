import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Bar-Fenster für einen Bildschirm. Positionswechsel: Bar fährt raus, Fenster wechselt
// die Kante, Bar fährt an der neuen Kante wieder rein.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    readonly property var cfg: BarConfig.current
    property string edge: "top"                 // tatsächlich verwendete Kante (folgt cfg.position mit Animation)
    Component.onCompleted: edge = BarConfig.current.position
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property var shownCfg: Object.assign({}, cfg, { position: edge })
    readonly property real thickness: cfg.size + (cfg.style === "docked" ? 0 : cfg.margin)

    color: "transparent"
    anchors {
        top: win.edge !== "bottom"
        bottom: win.edge !== "top"
        left: win.edge !== "right"
        right: win.edge !== "left"
    }
    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    exclusiveZone: thickness

    WlrLayershell.namespace: "sarch-bar"
    WlrLayershell.layer: WlrLayer.Top

    // nur die sichtbaren Teile der Bar fangen Klicks (Lücken bleiben durchlässig)
    mask: Region {
        item: content.barItem
    }

    Connections {
        target: BarConfig
        function onCurrentChanged() {
            if (BarConfig.current.position !== win.edge) {
                content.shown = false;
                swap.restart();
            }
        }
    }
    Timer {
        id: swap

        interval: 280
        onTriggered: {
            win.edge = BarConfig.current.position;
            content.shown = true;
        }
    }

    BarContent {
        id: content

        anchors.fill: parent
        cfg: win.shownCfg
        screen: win.screen
        shown: false
        Component.onCompleted: Qt.callLater(() => shown = true)
    }
}
