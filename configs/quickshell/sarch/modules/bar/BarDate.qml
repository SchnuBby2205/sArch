import QtQuick
import qs.components
import qs.services

// Datum; vertikal als Tag über Monat
Item {
    id: root

    property var cfg
    property bool vertical: false
    property real thick: 40

    readonly property var loc: Qt.locale(Backend.locale)
    readonly property string fmt: cfg?.date?.format || "ddd, d. MMM"
    readonly property string dayKey: Time.now.toDateString()

    implicitWidth: vertical ? thick : label.implicitWidth + 18
    implicitHeight: vertical ? col.implicitHeight + 12 : thick

    Txt {
        id: label

        visible: !root.vertical
        anchors.centerIn: parent
        text: { root.dayKey; return Time.now.toLocaleDateString(root.loc, root.fmt); }
        font.pixelSize: Math.round(Math.min(root.thick * 0.33 * Theme.fontScale, root.thick * 0.5))
        font.weight: Font.Medium
        color: Theme.barFgDim(root.cfg)
    }

    Column {
        id: col

        visible: root.vertical
        anchors.centerIn: parent
        spacing: -2

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: { root.dayKey; return Time.now.toLocaleDateString(root.loc, "dd"); }
            font.pixelSize: Math.round(Math.min(root.thick * 0.36 * Theme.fontScale, root.thick * 0.5))
            font.weight: Font.Bold
            color: Theme.barFg(root.cfg)
        }
        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: { root.dayKey; return Time.now.toLocaleDateString(root.loc, "MMM").replace(".", "").toUpperCase(); }
            font.pixelSize: Math.round(Math.min(root.thick * 0.24 * Theme.fontScale, root.thick * 0.36))
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            color: Theme.primary
        }
    }
}
