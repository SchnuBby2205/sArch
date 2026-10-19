import QtQuick
import qs.services

// kleiner Tooltip über dem Parent
Rectangle {
    id: root

    property string text: ""
    property bool shown: false

    z: 1000
    anchors.bottom: parent.top
    anchors.bottomMargin: 8
    anchors.horizontalCenter: parent.horizontalCenter
    width: label.implicitWidth + 20
    height: 28
    radius: 8
    color: Theme.surfaceHighest
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.85
    visible: opacity > 0

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation {
                duration: root.shown ? 350 : 0
            }
            Anim {
                curve: "effects"
            }
        }
    }
    Behavior on scale {
        Anim {
            curve: "spatialFast"
        }
    }

    Txt {
        id: label

        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Theme.size.small
        color: Theme.surfaceFg
    }
}
