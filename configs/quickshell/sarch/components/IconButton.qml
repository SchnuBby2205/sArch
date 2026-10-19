import QtQuick
import qs.services

// Runder Icon-Button; variant: standard | tonal | filled | danger
// Expressive: Ecken morphen beim Drücken, Icon füllt sich beim Hovern.
Rectangle {
    id: root

    property string icon: ""
    property string variant: "standard"
    property real size: 40
    property real iconSize: size * 0.55
    property bool active: false
    property bool disabled: false
    property string tooltip: ""

    signal clicked

    implicitWidth: size
    implicitHeight: size
    radius: area.pressed ? size * 0.28 : size / 2
    opacity: disabled ? 0.38 : 1
    color: variant === "filled" ? Theme.primary
         : variant === "tonal" ? Theme.secondaryContainer
         : variant === "danger" ? Theme.alpha(Theme.error, area.containsMouse ? 0.16 : 0)
         : active ? Theme.alpha(Theme.primary, 0.16) : "transparent"

    Behavior on radius {
        Anim {
            curve: "spatialFast"
        }
    }
    Behavior on color {
        CAnim {}
    }
    Behavior on opacity {
        Anim {
            curve: "effects"
        }
    }

    Icon {
        anchors.centerIn: parent
        icon: root.icon
        size: root.iconSize
        fill: area.containsMouse || root.active ? 1 : 0
        color: root.variant === "filled" ? Theme.primaryFg
             : root.variant === "tonal" ? Theme.secondaryContainerFg
             : root.variant === "danger" ? Theme.error
             : root.active ? Theme.primary : Theme.surfaceFgDim
        scale: area.pressed ? 0.86 : 1

        Behavior on scale {
            Anim {
                curve: "spatialFast"
            }
        }
    }

    StateLayer {
        id: area

        disabled: root.disabled
        tint: root.variant === "filled" ? Theme.primaryFg : root.variant === "danger" ? Theme.error : Theme.surfaceFg
        onClicked: root.clicked()
    }

    Tip {
        text: root.tooltip
        shown: area.containsMouse && root.tooltip !== ""
    }
}
