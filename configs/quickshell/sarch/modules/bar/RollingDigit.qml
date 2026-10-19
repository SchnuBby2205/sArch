import QtQuick
import qs.components
import qs.services

// Ziffer, die beim Wechsel nach oben "wegrollt" und die neue von unten nachschiebt
Item {
    id: root

    property string digit: "0"
    property int pixelSize: 16
    property color color: Theme.surfaceFg
    property int weight: Font.DemiBold

    // Oberflächen-Schrift; Breite = breiteste Ziffer, damit nichts springt
    implicitWidth: Math.ceil(Math.max(...("0123456789".split("").map(d => fm.advanceWidth(d)))) + root.pixelSize * 0.04)
    implicitHeight: metrics.height
    clip: true

    property string oldDigit: digit
    property real progress: 1

    onDigitChanged: {
        roll.stop();
        progress = 0;
        roll.start();
    }

    TextMetrics {
        id: metrics

        font.family: Theme.sans
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        text: "0"
    }

    FontMetrics {
        id: fm
        font: metrics.font
    }

    Text {
        id: outgoing

        text: root.oldDigit
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        y: -root.height * root.progress
        opacity: 1 - root.progress
        font: metrics.font
        color: root.color
        renderType: Text.NativeRendering
    }
    Text {
        text: root.digit
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        y: root.height * (1 - root.progress)
        opacity: root.progress
        font: metrics.font
        color: root.color
        renderType: Text.NativeRendering
    }

    Anim {
        id: roll

        target: root
        property: "progress"
        from: 0
        to: 1
        curve: "spatialFast"
        duration: 420
        onFinished: root.oldDigit = root.digit
    }
}
