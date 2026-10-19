import QtQuick
import qs.services

// Tastenkappe mit "3D"-Kante
Item {
    id: root

    property string label: ""
    property bool accent: false

    implicitWidth: Math.max(28, txt.implicitWidth + 16)
    implicitHeight: 28

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.accent ? Theme.mix(Theme.primaryContainer, Theme.surfaceLowest, 0.35) : Theme.surfaceLowest
    }
    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: 3
        radius: 8
        color: root.accent ? Theme.primaryContainer : Theme.surfaceHighest
        border.width: 1
        border.color: Theme.alpha(Theme.outline, 0.25)

        Txt {
            id: txt

            anchors.centerIn: parent
            text: root.label
            font.pixelSize: Theme.size.small
            font.weight: Font.DemiBold
            color: root.accent ? Theme.primaryContainerFg : Theme.surfaceFg
        }
    }
}
