import QtQuick
import QtQuick.Effects
import qs.services

// Glas-Fläche: geblurrtes Wallpaper, getönt, mit runden Ecken, Rahmen und Schatten
Item {
    id: root

    property real radius: Theme.radius.xl
    property real tint: 0.80
    property bool shadow: true
    property real blurAmount: 1.0

    Rectangle {
        id: shadowSrc

        anchors.fill: parent
        radius: root.radius
        color: "black"
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        visible: root.shadow
        anchors.fill: shadowSrc
        source: shadowSrc
        shadowEnabled: true
        shadowColor: "black"
        shadowBlur: 1.0
        shadowOpacity: 0.55
        shadowVerticalOffset: 16
        autoPaddingEnabled: true
    }

    Image {
        id: wp

        anchors.fill: parent
        visible: false
        source: Theme.wallpaper !== "" ? "file://" + Theme.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 960
        asynchronous: true
    }
    Rectangle {
        id: mask

        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: wp
        blurEnabled: true
        blur: root.blurAmount
        blurMax: 64
        blurMultiplier: 1.4
        saturation: 0.25
        brightness: -0.08
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.alpha(Theme.surface, root.tint)
        border.width: 1
        border.color: Theme.alpha(Theme.outline, 0.22)
    }
}
