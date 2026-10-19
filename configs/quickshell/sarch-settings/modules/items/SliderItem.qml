import QtQuick
import qs.components
import qs.services

Card {
    id: root

    required property var item
    required property var page

    readonly property real original: item.value
    property real value: item.value
    readonly property bool modified: value !== original

    width: parent?.width ?? 400
    height: 112
    highlighted: modified

    function sync() {
        page.setPending(item.uid, modified ? { uid: item.uid, value: value } : null);
    }

    Connections {
        target: root.page
        function onResetTokenChanged() {
            root.value = root.original;
            slider.value = root.original;
        }
    }

    Column {
        x: 22
        y: 18
        width: parent.width - 44 - valueChip.width
        spacing: 3

        Txt {
            width: parent.width
            text: root.item.label
            font.pixelSize: Theme.size.label
            font.weight: Font.Medium
        }
        Txt {
            width: parent.width
            text: root.item.description
            visible: text !== ""
            font.pixelSize: Theme.size.small
            color: Theme.surfaceFgDim
        }
    }

    Rectangle {
        id: valueChip

        anchors.right: parent.right
        anchors.rightMargin: 18
        y: 16
        width: Math.max(56, vtxt.implicitWidth + 24 + (root.modified ? 30 : 0))
        height: 34
        radius: 17
        color: root.modified ? Theme.tertiaryContainer : Theme.surfaceHighest
        Behavior on width { Anim { curve: "spatialFast" } }
        Behavior on color { CAnim {} }

        Txt {
            id: vtxt

            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Number(root.value.toFixed(slider.decimals))
            mono: true
            font.pixelSize: Theme.size.label
            font.weight: Font.Bold
            color: root.modified ? Theme.tertiaryContainerFg : Theme.surfaceFg

            Behavior on text {
                SequentialAnimation {
                    Anim { target: vtxt; property: "scale"; to: 1.18; duration: 70; curve: "standard" }
                    PropertyAction {}
                    Anim { target: vtxt; property: "scale"; to: 1; curve: "spatialFast" }
                }
            }
        }
        IconButton {
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            size: 28
            icon: "undo"
            visible: root.modified
            opacity: root.modified ? 1 : 0
            tooltip: Backend.t("btn_reset", "Zurücksetzen")
            onClicked: {
                root.value = root.original;
                slider.value = root.original;
                root.sync();
            }
        }
    }

    Txt {
        x: 22
        anchors.verticalCenter: slider.verticalCenter
        text: root.item.min
        mono: true
        font.pixelSize: Theme.size.tiny
        color: Theme.surfaceFgDim
    }
    SSlider {
        id: slider

        x: 54
        width: parent.width - 108
        y: 62
        from: root.item.min
        to: root.item.max
        stepSize: root.item.step
        value: root.item.value
        onMoved: v => {
            root.value = v;
            root.sync();
        }
    }
    Txt {
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: slider.verticalCenter
        text: root.item.max
        mono: true
        font.pixelSize: Theme.size.tiny
        color: Theme.surfaceFgDim
    }
}
