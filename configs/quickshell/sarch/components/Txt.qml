import QtQuick
import qs.services

Text {
    property bool mono: false

    color: Theme.surfaceFg
    // überall die Oberflächen-Schrift; "mono" sorgt nur für gleich breite Ziffern (Werte, Zähler)
    font.family: Theme.sans
    font.features: mono ? { "tnum": 1 } : ({})
    font.pixelSize: Theme.size.body
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering

    Behavior on color {
        CAnim {}
    }
}
