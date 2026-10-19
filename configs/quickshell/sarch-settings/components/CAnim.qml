import QtQuick
import qs.services

ColorAnimation {
    duration: 250
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.anim.curves.standard
}
