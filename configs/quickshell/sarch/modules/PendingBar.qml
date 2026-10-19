import QtQuick
import qs.components
import qs.services

// schwebende Leiste für nicht übernommene Änderungen
Rectangle {
    id: root

    property int count: 0
    property bool busy: false
    readonly property bool shown: count > 0 || busy

    width: row.implicitWidth + 28
    height: 60
    radius: 30
    color: Theme.surfaceHighest
    border.width: 1
    border.color: Theme.alpha(Theme.primary, 0.35)

    property real dy: shown ? 0 : 110
    transform: Translate { y: root.dy }
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.8
    Behavior on dy { Anim { curve: root.shown ? "spatialSlow" : "emphasizedAccel" } }
    Behavior on opacity { Anim { curve: "effects"; duration: 250 } }
    Behavior on scale { Anim { curve: "spatial" } }
    Behavior on width { Anim { curve: "spatialFast" } }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 10

        Rectangle {
            width: 36
            height: 36
            radius: 18
            color: Theme.tertiaryContainer
            anchors.verticalCenter: parent.verticalCenter

            Txt {
                id: num

                anchors.centerIn: parent
                text: root.count
                mono: true
                font.weight: Font.Bold
                color: Theme.tertiaryContainerFg

                Behavior on text {
                    SequentialAnimation {
                        Anim { target: num; property: "scale"; to: 0.4; duration: 90; curve: "standard" }
                        PropertyAction {}
                        Anim { target: num; property: "scale"; to: 1; curve: "spatialFast" }
                    }
                }
            }
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.count === 1 ? Backend.t("qs_pending_one", "ungespeicherte Änderung") : Backend.t("qs_pending_many", "ungespeicherte Änderungen")
            font.weight: Font.Medium
            rightPadding: 12
        }
        Btn {
            anchors.verticalCenter: parent.verticalCenter
            variant: "text"
            icon: "undo"
            text: Backend.t("btn_reset", "Zurücksetzen")
            disabled: root.busy
            onClicked: Ui.requestReset()
        }
        Btn {
            anchors.verticalCenter: parent.verticalCenter
            variant: "filled"
            icon: "done_all"
            busy: root.busy
            text: Backend.t("btn_apply", "Übernehmen")
            onClicked: Ui.requestApply()
        }
    }
}
