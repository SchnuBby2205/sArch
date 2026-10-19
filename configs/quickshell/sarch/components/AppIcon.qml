import QtQuick
import Quickshell
import qs.services

// Icon eines Desktop-Eintrags; ohne passendes Theme-Icon ein Buchstaben-Badge
Item {
    id: root

    property var entry
    property real size: 48

    readonly property string path: entry && entry.icon ? (entry.icon.startsWith("/") ? entry.icon : Quickshell.iconPath(entry.icon, true)) : ""

    implicitWidth: size
    implicitHeight: size

    Image {
        id: img

        anchors.fill: parent
        source: root.path !== "" ? (root.path.startsWith("/") ? "file://" + root.path : root.path) : ""
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        visible: img.status !== Image.Ready
        radius: root.size * 0.3
        color: Theme.primaryContainer

        Txt {
            anchors.centerIn: parent
            text: (root.entry?.name ?? "?").charAt(0).toUpperCase()
            font.pixelSize: root.size * 0.5
            font.weight: Font.Bold
            color: Theme.primaryContainerFg
        }
    }
}
