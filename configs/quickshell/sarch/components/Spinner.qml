import QtQuick
import QtQuick.Shapes
import qs.services

// Material-artiger Ladekreis: Bogen dreht sich und "atmet" in der Länge.
Item {
    id: root

    property color color: Theme.primary
    property real stroke: 3.5
    property bool running: visible

    implicitWidth: 28
    implicitHeight: 28

    Shape {
        id: shape

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        property real sweep: 40

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - root.stroke
                radiusY: root.height / 2 - root.stroke
                startAngle: -90
                sweepAngle: shape.sweep
            }
        }

        RotationAnimation on rotation {
            running: root.running
            from: 0
            to: 360
            duration: 1100
            loops: Animation.Infinite
        }

        SequentialAnimation on sweep {
            running: root.running
            loops: Animation.Infinite

            NumberAnimation {
                from: 30
                to: 270
                duration: 700
                easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                from: 270
                to: 30
                duration: 700
                easing.type: Easing.InOutCubic
            }
        }
    }
}
