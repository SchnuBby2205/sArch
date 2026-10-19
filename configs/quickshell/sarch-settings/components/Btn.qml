import QtQuick
import qs.services

// Text-Button mit optionalem Icon. variant: filled | tonal | outlined | text | danger
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property string variant: "filled"
    property bool busy: false
    property bool disabled: false
    property real h: 40

    signal clicked

    implicitWidth: row.implicitWidth + (icon !== "" ? 36 : 44)
    implicitHeight: h
    radius: area.pressed ? 12 : h / 2
    opacity: disabled ? 0.38 : 1
    scale: area.pressed ? 0.97 : 1

    readonly property color fg: variant === "filled" ? Theme.primaryFg
                              : variant === "tonal" ? Theme.secondaryContainerFg
                              : variant === "danger" ? Theme.errorFg
                              : Theme.primary

    color: variant === "filled" ? Theme.primary
         : variant === "tonal" ? Theme.secondaryContainer
         : variant === "danger" ? Theme.error
         : "transparent"
    border.width: variant === "outlined" ? 1 : 0
    border.color: Theme.outline

    Behavior on radius {
        Anim {
            curve: "spatialFast"
        }
    }
    Behavior on scale {
        Anim {
            curve: "spatialFast"
        }
    }
    Behavior on color {
        CAnim {}
    }
    Behavior on implicitWidth {
        Anim {
            curve: "spatialFast"
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 8

        Item {
            width: root.busy || root.icon !== "" ? 20 : 0
            height: 20
            visible: width > 0
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                anchors.centerIn: parent
                icon: root.icon
                size: 20
                color: root.fg
                opacity: root.busy ? 0 : 1
                scale: root.busy ? 0.4 : 1
                Behavior on opacity { Anim { curve: "effects" } }
                Behavior on scale { Anim { curve: "spatialFast" } }
            }
            Spinner {
                anchors.centerIn: parent
                width: 18
                height: 18
                stroke: 2.5
                color: root.fg
                opacity: root.busy ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { Anim { curve: "effects" } }
            }
        }

        Txt {
            text: root.text
            color: root.fg
            font.pixelSize: Theme.size.body
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StateLayer {
        id: area

        disabled: root.disabled || root.busy
        tint: root.fg
        onClicked: root.clicked()
    }
}
