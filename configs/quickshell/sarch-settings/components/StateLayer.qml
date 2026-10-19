import QtQuick
import qs.services

// Hover-/Press-Schicht: füllt den Parent, Ton passt sich an, "Bloom" wächst vom Klickpunkt aus.
MouseArea {
    id: root

    property color tint: Theme.surfaceFg
    property real radius: parent?.radius ?? 0
    property bool disabled: false
    property real hoverOpacity: 0.08

    anchors.fill: parent
    hoverEnabled: true
    enabled: !disabled
    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        opacity: root.disabled ? 0 : root.pressed ? 0.14 : root.containsMouse ? root.hoverOpacity : 0

        Behavior on opacity {
            Anim {
                curve: "effects"
            }
        }
    }

    Rectangle {
        id: bloom

        property real px: root.width / 2
        property real py: root.height / 2
        property real s: 0

        anchors.fill: parent
        radius: root.radius
        color: root.tint
        opacity: 0
        transform: Scale {
            origin.x: bloom.px
            origin.y: bloom.py
            xScale: bloom.s
            yScale: bloom.s
        }

        ParallelAnimation {
            id: bloomAnim

            Anim {
                target: bloom
                property: "s"
                from: 0
                to: 1
                curve: "emphasizedDecel"
                duration: 450
            }
            SequentialAnimation {
                NumberAnimation {
                    target: bloom
                    property: "opacity"
                    to: 0.12
                    duration: 60
                }
                PauseAnimation {
                    duration: 200
                }
                NumberAnimation {
                    target: bloom
                    property: "opacity"
                    to: 0
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    onPressed: e => {
        bloom.px = e.x;
        bloom.py = e.y;
        bloomAnim.restart();
    }
}
