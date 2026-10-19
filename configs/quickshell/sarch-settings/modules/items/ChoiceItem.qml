import QtQuick
import qs.components
import qs.services

Card {
    id: root

    required property var item
    required property var page

    readonly property string original: item.value
    property string value: item.value
    readonly property bool modified: value !== original
    readonly property var options: {
        const o = item.options.slice();
        if (original !== "" && o.indexOf(original) < 0)
            o.unshift(original);   // unbekannten Ist-Wert nicht stillschweigend überschreiben
        return o;
    }
    readonly property bool segmented: options.length <= 4 && options.join("").length <= 30

    width: parent?.width ?? 400
    height: segmented && width < 640 ? 124 : 80
    highlighted: modified

    function pick(v) {
        value = v;
        page.setPending(item.uid, modified ? { uid: item.uid, value: v } : null);
    }

    Connections {
        target: root.page
        function onResetTokenChanged() {
            root.value = root.original;
        }
    }

    Column {
        x: 22
        y: root.height > 100 ? 18 : (root.height - height) / 2
        width: root.height > 100 ? parent.width - 44 : parent.width - 66 - chooser.width
        spacing: 3

        Row {
            spacing: 8

            Txt {
                text: root.item.label
                font.pixelSize: Theme.size.label
                font.weight: Font.Medium
            }
            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: Theme.tertiary
                anchors.verticalCenter: parent.verticalCenter
                scale: root.modified ? 1 : 0
                Behavior on scale { Anim { curve: "spatialFast" } }
            }
        }
        Txt {
            width: parent.width
            text: root.item.description
            visible: text !== ""
            font.pixelSize: Theme.size.small
            color: Theme.surfaceFgDim
        }
    }

    Loader {
        id: chooser

        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.bottom: root.height > 100 ? parent.bottom : undefined
        anchors.bottomMargin: 16
        anchors.verticalCenter: root.height > 100 ? undefined : parent.verticalCenter
        sourceComponent: root.segmented ? seg : sel
    }

    Component {
        id: seg

        Segmented {
            options: root.options
            value: root.value
            onPicked: v => root.pick(v)
        }
    }
    Component {
        id: sel

        Select {
            width: 260
            options: root.options
            value: root.value
            modified: root.modified
            mono: /\d+x\d+/.test(root.options[0] || "")
            onPicked: v => root.pick(v)
        }
    }
}
