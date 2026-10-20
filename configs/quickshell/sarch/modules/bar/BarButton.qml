import QtQuick
import qs.components
import qs.services

// Icon-Knopf in der Bar: Bloom beim Klick, Icon füllt sich & "hüpft" beim Hovern
Item {
    id: root

    property string icon: ""
    property var cfg: BarConfig.current     // für Schriftfarbe (Vorschau in den Einstellungen: Entwurf)
    property real thick: 40
    property bool vertical: false
    property color accent: Theme.primary
    property string label: ""          // optionaler Text neben dem Icon (nur horizontal)
    property bool active: false
    property int badge: 0               // Zähler oben rechts (0 = aus)
    property real iconRotation: 0       // z. B. Glocke wackeln lassen

    signal clicked
    signal middleClicked
    signal rightClicked
    signal wheel(int delta)

    readonly property real cell: thick - 10
    implicitWidth: vertical ? thick : cell + (labelTxt.visible ? labelTxt.implicitWidth + 6 : 0) + 4
    implicitHeight: vertical ? cell + 4 : thick

    Rectangle {
        id: bg

        anchors.centerIn: parent
        width: root.vertical ? root.cell : root.implicitWidth - 4
        height: root.vertical ? root.cell : root.cell
        radius: area.pressed ? root.cell * 0.3 : root.cell / 2
        color: root.active ? Theme.alpha(root.accent, 0.2) : "transparent"
        Behavior on radius { Anim { curve: "spatialFast" } }

        StateLayer {
            id: area

            tint: root.accent
            hoverOpacity: 0.14
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: e => e.button === Qt.MiddleButton ? root.middleClicked() : e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
            onWheel: e => root.wheel(e.angleDelta.y)
        }

        Row {
            anchors.centerIn: parent
            spacing: 6

            Icon {
                id: ico

                icon: root.icon
                size: root.cell * 0.62
                fill: area.containsMouse || root.active ? 1 : 0
                color: area.containsMouse || root.active ? root.accent : Theme.barFg(root.cfg)
                anchors.verticalCenter: parent.verticalCenter
                scale: area.pressed ? 0.8 : area.containsMouse ? 1.12 : 1
                rotation: (area.containsMouse && root.icon === "settings" ? 90 : 0) + root.iconRotation
                Behavior on scale { Anim { curve: "spatialFast" } }
                Behavior on rotation { Anim { curve: "spatialSlow" } }
            }
            Txt {
                id: labelTxt

                visible: !root.vertical && root.label !== ""
                text: root.label
                font.pixelSize: Math.round(Math.min(root.thick * 0.3 * Theme.fontScale, root.thick * 0.46))
                font.weight: Font.DemiBold
                color: Theme.barFgDim(root.cfg)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Zähler (z. B. ungelesene Benachrichtigungen)
    Rectangle {
        id: badgeBox

        readonly property bool on: root.badge > 0
        anchors.horizontalCenter: bg.horizontalCenter
        anchors.horizontalCenterOffset: root.cell * 0.28
        anchors.verticalCenter: bg.verticalCenter
        anchors.verticalCenterOffset: -root.cell * 0.26
        width: Math.max(16, badgeTxt.implicitWidth + 8)
        height: 16
        radius: 8
        color: root.accent
        border.width: 2
        border.color: Theme.surface
        scale: on ? 1 : 0
        Behavior on scale { Anim { curve: "spatialFast" } }

        Txt {
            id: badgeTxt

            anchors.centerIn: parent
            text: root.badge > 9 ? "9+" : String(root.badge)
            font.pixelSize: 9
            font.weight: Font.Bold
            color: Theme.surface
        }
    }
}
