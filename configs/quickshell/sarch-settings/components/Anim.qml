import QtQuick
import qs.services

// NumberAnimation mit Material-3-Expressive-Kurven: curve = spatial | spatialFast | spatialSlow |
// emphasized | emphasizedDecel | emphasizedAccel | standard | decel | effects
NumberAnimation {
    property string curve: "spatial"

    duration: Theme.anim.durations[curve] ?? 400
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.anim.curves[curve] ?? Theme.anim.curves.standard
}
