import QtQuick
import qs.components
import qs.services

// Uhrzeit mit rollenden Ziffern; vertikal gestapelt
Item {
    id: root

    property var cfg
    property bool vertical: false
    property real thick: 40

    readonly property bool seconds: cfg?.clock?.seconds ?? false
    readonly property bool h24: cfg?.clock?.h24 ?? true
    readonly property bool blink: cfg?.clock?.blink ?? true
    readonly property int hours: h24 ? Time.now.getHours() : ((Time.now.getHours() + 11) % 12) + 1
    readonly property string hh: (h24 ? String(hours).padStart(2, "0") : String(hours).padStart(2, " "))
    readonly property string mm: String(Time.now.getMinutes()).padStart(2, "0")
    readonly property string ss: String(Time.now.getSeconds()).padStart(2, "0")
    readonly property int fontSize: Math.round(thick * (vertical ? 0.36 : 0.4))

    implicitWidth: vertical ? thick : row.implicitWidth + 16
    implicitHeight: vertical ? col.implicitHeight + 14 : thick

    Row {
        id: row

        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 0

        RollingDigit { digit: root.hh[0]; pixelSize: root.fontSize }
        RollingDigit { digit: root.hh[1]; pixelSize: root.fontSize }
        Txt {
            text: ":"
            mono: true
            font.pixelSize: root.fontSize
            font.weight: Font.DemiBold
            color: Theme.primary
            opacity: !root.blink || Time.now.getSeconds() % 2 === 0 ? 1 : 0.35
            Behavior on opacity { Anim { curve: "standard" } }
        }
        RollingDigit { digit: root.mm[0]; pixelSize: root.fontSize }
        RollingDigit { digit: root.mm[1]; pixelSize: root.fontSize }
        Item {
            visible: root.seconds
            width: visible ? secRow.implicitWidth + 4 : 0
            height: parent.height

            Row {
                id: secRow

                x: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                RollingDigit { digit: root.ss[0]; pixelSize: root.fontSize * 0.62; color: Theme.surfaceFgDim }
                RollingDigit { digit: root.ss[1]; pixelSize: root.fontSize * 0.62; color: Theme.surfaceFgDim }
            }
        }
        Txt {
            visible: !root.h24
            leftPadding: 5
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            text: Time.now.getHours() < 12 ? "AM" : "PM"
            font.pixelSize: root.fontSize * 0.55
            font.weight: Font.Bold
            color: Theme.surfaceFgDim
        }
    }

    Column {
        id: col

        visible: root.vertical
        anchors.centerIn: parent
        spacing: -2

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            RollingDigit { digit: root.hh[0]; pixelSize: root.fontSize; color: Theme.primary }
            RollingDigit { digit: root.hh[1]; pixelSize: root.fontSize; color: Theme.primary }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            RollingDigit { digit: root.mm[0]; pixelSize: root.fontSize }
            RollingDigit { digit: root.mm[1]; pixelSize: root.fontSize }
        }
        Row {
            visible: root.seconds
            anchors.horizontalCenter: parent.horizontalCenter
            RollingDigit { digit: root.ss[0]; pixelSize: root.fontSize * 0.7; color: Theme.surfaceFgDim }
            RollingDigit { digit: root.ss[1]; pixelSize: root.fontSize * 0.7; color: Theme.surfaceFgDim }
        }
    }
}
