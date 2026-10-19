import QtQuick
import qs.services

// Material Symbols Rounded (Ligatur), mit animierbarer Füllung
Text {
    id: root

    property string icon: ""
    property real fill: 0
    property int weight: 400
    property real size: 22

    text: icon
    color: Theme.surfaceFg
    font.family: Theme.icons
    font.pixelSize: size
    font.variableAxes: ({
            "FILL": root.fill,
            "wght": root.weight,
            "opsz": Math.max(20, Math.min(48, root.size)),
            "GRAD": 0
        })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering

    Behavior on fill {
        Anim {
            curve: "standard"
        }
    }
    Behavior on color {
        CAnim {}
    }
}
