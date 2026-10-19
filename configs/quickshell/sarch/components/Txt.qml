import QtQuick
import qs.services

Text {
    property bool mono: false

    color: Theme.surfaceFg
    font.family: mono ? Theme.mono : Theme.sans
    font.pixelSize: Theme.size.body
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering

    Behavior on color {
        CAnim {}
    }
}
