import QtQuick
import qs.services

// Gestapelte Toasts, gleiten von unten rein, laufen mit Fortschrittslinie ab.
Item {
    id: root

    width: 420
    height: col.implicitHeight

    Column {
        id: col

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        move: Transition {
            Anim { property: "y"; curve: "spatial" }
        }

        Repeater {
            model: Ui.toasts

            Rectangle {
                id: toast

                required property int tid
                required property string text
                required property string icon
                required property string kind

                readonly property color accent: kind === "error" ? Theme.error : kind === "busy" ? Theme.secondary : Theme.primary

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(root.width, row.implicitWidth + 40)
                height: 52
                radius: 26
                color: Theme.surfaceHighest
                border.width: 1
                border.color: Theme.alpha(accent, 0.35)

                opacity: 0
                scale: 0.7
                property real dy: 30
                transform: Translate { y: toast.dy }

                Component.onCompleted: inAnim.start()

                ParallelAnimation {
                    id: inAnim

                    Anim { target: toast; property: "opacity"; to: 1; curve: "effects"; duration: 250 }
                    Anim { target: toast; property: "scale"; to: 1; curve: "spatialFast" }
                    Anim { target: toast; property: "dy"; to: 0; curve: "spatial" }
                }
                SequentialAnimation {
                    id: outAnim

                    ParallelAnimation {
                        Anim { target: toast; property: "opacity"; to: 0; curve: "emphasizedAccel" }
                        Anim { target: toast; property: "scale"; to: 0.85; curve: "emphasizedAccel" }
                    }
                    ScriptAction { script: Ui.dropToast(toast.tid) }
                }

                Rectangle {
                    id: progress

                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    x: 26
                    height: 3
                    radius: 1.5
                    color: toast.accent
                    opacity: 0.6
                    width: toast.width - 52
                    NumberAnimation on width {
                        from: toast.width - 52
                        to: 0
                        duration: toast.kind === "error" ? 6000 : 3200
                        running: toast.kind !== "busy"
                        onFinished: outAnim.start()
                    }
                }

                Row {
                    id: row

                    anchors.centerIn: parent
                    spacing: 10

                    Icon {
                        icon: toast.icon
                        fill: 1
                        size: 22
                        color: toast.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: toast.text
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: outAnim.start()
                }
            }
        }
    }
}
