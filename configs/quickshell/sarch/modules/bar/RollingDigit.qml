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

    implicitWidth: metrics.advanceWidth
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

        font.family: Theme.mono
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        text: "0"
    }

    Text {
        id: outgoing

        text: root.oldDigit
        y: -root.height * root.progress
        opacity: 1 - root.progress
        font: metrics.font
        color: root.color
        renderType: Text.NativeRendering
    }
    Text {
        text: root.digit
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
