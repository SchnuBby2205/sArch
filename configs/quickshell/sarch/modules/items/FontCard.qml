import QtQuick
import QtQuick.Controls
import qs.components
import qs.services

// Eine Schrift-Karte: Live-Vorschau, Familien-Auswahl mit Suche, Größe
Card {
    id: root

    property string title: ""
    property string subtitle: ""
    property string icon: "text_fields"
    property var families: []
    property string family: ""
    property real size: 12
    property real minSize: 6
    property real maxSize: 40
    property real step: 1
    property string originalFamily: ""
    property real originalSize: 12
    readonly property bool modified: family !== originalFamily || size !== originalSize

    signal edited

    height: 330
    highlighted: modified

    // Kopf
    Row {
        x: 22
        y: 20
        spacing: 12

        Rectangle {
            width: 40
            height: 40
            radius: 13
            color: Theme.secondaryContainer

            Icon {
                anchors.centerIn: parent
                icon: root.icon
                size: 22
                color: Theme.secondaryContainerFg
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter

            Txt {
                text: root.title
                font.pixelSize: Theme.size.label
                font.weight: Font.Medium
            }
            Txt {
                text: root.subtitle
                font.pixelSize: Theme.size.small
                color: Theme.surfaceFgDim
            }
        }
    }

    // Vorschau
    Rectangle {
        id: previewBox

        x: 18
        y: 76
        width: parent.width - 36
        height: 128
        radius: Theme.radius.normal
        color: Theme.alpha(Theme.surfaceLowest, 0.55)
        clip: true

        Text {
            id: aa

            x: 18
            anchors.verticalCenter: parent.verticalCenter
            text: "Aa"
            font.family: root.family
            font.pixelSize: 64
            color: Theme.primary
            renderType: Text.NativeRendering
        }
        Column {
            anchors.left: aa.right
            anchors.leftMargin: 18
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                width: parent.width
                text: "Franz jagt im komplett verwahrlosten Taxi quer durch Bayern"
                font.family: root.family
                font.pixelSize: Math.round(root.size * 1.33)
                color: Theme.surfaceFg
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Behavior on font.pixelSize { Anim { curve: "spatialFast" } }
            }
            Text {
                width: parent.width
                text: "0123456789  {} [] => != ~/.config"
                font.family: root.family
                font.pixelSize: Math.round(root.size * 1.1)
                color: Theme.surfaceFgDim
                elide: Text.ElideRight
            }
        }
    }

    // Familie
    Rectangle {
        id: famBtn

        x: 18
        y: previewBox.y + previewBox.height + 14
        width: parent.width - 36
        height: 52
        radius: Theme.radius.small + 2
        color: picker.opened ? Theme.surfaceHighest : Theme.surfaceHigh
        border.width: picker.opened ? 2 : 1
        border.color: picker.opened ? Theme.primary : root.family !== root.originalFamily ? Theme.alpha(Theme.tertiary, 0.7) : Theme.alpha(Theme.outline, 0.35)

        Txt {
            x: 14
            y: 7
            text: Backend.t("font_family", "Schriftart")
            font.pixelSize: Theme.size.tiny
            color: Theme.surfaceFgDim
        }
        Text {
            x: 14
            y: 23
            width: parent.width - 60
            text: root.family || "—"
            font.family: root.family
            font.pixelSize: Theme.size.label
            color: Theme.surfaceFg
            elide: Text.ElideRight
        }
        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            icon: "unfold_more"
            color: Theme.surfaceFgDim
        }
        StateLayer {
            onClicked: {
                picker.open();
                search.text = "";
                search.forceFocus();
                famList.positionViewAtIndex(Math.max(0, root.families.indexOf(root.family)), ListView.Center);
            }
        }

        Popup {
            id: picker

            y: famBtn.height + 6
            width: famBtn.width
            height: 360
            padding: 8
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

            background: Rectangle {
                radius: Theme.radius.large
                color: Theme.surfaceHigh
                border.width: 1
                border.color: Theme.alpha(Theme.outline, 0.2)
            }
            enter: Transition {
                ParallelAnimation {
                    Anim { property: "opacity"; from: 0; to: 1; curve: "effects" }
                    Anim { property: "scale"; from: 0.9; to: 1; curve: "spatial" }
                }
            }
            exit: Transition {
                Anim { property: "opacity"; to: 0; curve: "emphasizedAccel" }
            }

            contentItem: Item {
                Field {
                    id: search

                    width: parent.width
                    compact: true
                    icon: "search"
                    placeholder: Backend.t("qs_font_search", "Schrift suchen …")
                }
                ListView {
                    id: famList

                    y: search.height + 8
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: {
                        const q = search.text.toLowerCase();
                        return q === "" ? root.families : root.families.filter(f => f.toLowerCase().includes(q));
                    }
                    Txt {
                        anchors.centerIn: parent
                        visible: famList.count === 0
                        text: Backend.t("qs_no_results", "Nichts gefunden für „{q}“", { q: search.text })
                        color: Theme.surfaceFgDim
                    }

                    delegate: Rectangle {
                        id: fd

                        required property string modelData
                        readonly property bool sel: modelData === root.family

                        width: famList.width
                        height: 44
                        radius: Theme.radius.small
                        color: sel ? Theme.secondaryContainer : "transparent"

                        Text {
                            x: 14
                            width: parent.width - 120
                            anchors.verticalCenter: parent.verticalCenter
                            text: fd.modelData
                            font.family: fd.modelData
                            font.pixelSize: Theme.size.label
                            color: fd.sel ? Theme.secondaryContainerFg : Theme.surfaceFg
                            elide: Text.ElideRight
                        }
                        Txt {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: fd.modelData
                            font.pixelSize: Theme.size.tiny
                            color: Theme.surfaceFgDim
                            width: 90
                            horizontalAlignment: Text.AlignRight
                        }
                        StateLayer {
                            onClicked: {
                                root.family = fd.modelData;
                                root.edited();
                                picker.close();
                            }
                        }
                    }
                }
            }
        }
    }

    // Größe
    Row {
        x: 18
        y: famBtn.y + famBtn.height + 14
        spacing: 10

        IconButton {
            icon: "remove"
            variant: "tonal"
            size: 38
            anchors.verticalCenter: parent.verticalCenter
            onClicked: {
                root.size = Math.max(root.minSize, root.size - root.step);
                root.edited();
            }
        }
        Rectangle {
            width: 76
            height: 38
            radius: 19
            color: root.size !== root.originalSize ? Theme.tertiaryContainer : Theme.surfaceHighest
            anchors.verticalCenter: parent.verticalCenter

            Txt {
                anchors.centerIn: parent
                text: Number(root.size.toFixed(1)) + " pt"
                mono: true
                font.weight: Font.Bold
                color: root.size !== root.originalSize ? Theme.tertiaryContainerFg : Theme.surfaceFg
            }
        }
        IconButton {
            icon: "add"
            variant: "tonal"
            size: 38
            anchors.verticalCenter: parent.verticalCenter
            onClicked: {
                root.size = Math.min(root.maxSize, root.size + root.step);
                root.edited();
            }
        }
        SSlider {
            width: root.width - 36 - 3 * 10 - 38 * 2 - 76
            anchors.verticalCenter: parent.verticalCenter
            from: root.minSize
            to: root.maxSize
            stepSize: root.step
            value: root.size
            suffix: " pt"
            onMoved: v => {
                root.size = v;
                root.edited();
            }
        }
    }
}
