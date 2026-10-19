import QtQuick
import qs.services

// Karte mit gestaffeltem Einblenden (order) und dezentem Hover-Lift
Rectangle {
    id: root

    property int order: 0
    property bool animateIn: true
    property bool hoverLift: true
    property bool highlighted: false
    readonly property bool hovered: hover.hovered

    property real dy: animateIn ? 28 : 0

    radius: Theme.radius.large
    color: Theme.alpha(highlighted ? Theme.surfaceHighest : Theme.surfaceHigh, highlighted ? 0.9 : 0.62)
    border.width: 1
    border.color: highlighted ? Theme.alpha(Theme.primary, 0.45) : Theme.alpha(Theme.outline, hovered ? 0.28 : 0.12)
    opacity: animateIn ? 0 : 1
    transform: Translate {
        y: root.dy
    }

    Behavior on color { CAnim { duration: 300 } }
    Behavior on border.color { CAnim { duration: 300 } }

    HoverHandler {
        id: hover
    }

    SequentialAnimation {
        id: reveal

        PauseAnimation {
            duration: Math.min(root.order, 14) * 38
        }
        ParallelAnimation {
            Anim { target: root; property: "opacity"; to: 1; curve: "effects"; duration: 320 }
            Anim { target: root; property: "dy"; to: 0; curve: "spatialSlow" }
        }
    }

    Component.onCompleted: if (animateIn)
        reveal.start()
}
