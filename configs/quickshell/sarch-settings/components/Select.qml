import QtQuick
import QtQuick.Controls
import qs.services

// Dropdown mit animiertem Aufklapp-Menü
Rectangle {
    id: root

    property var options: []
    property string value: ""
    property string label: ""
    property bool modified: false
    property bool mono: false

    signal picked(string value)

    implicitWidth: 240
    implicitHeight: label !== "" ? 56 : 40
    radius: Theme.radius.small + 2
    color: menu.opened ? Theme.surfaceHighest : Theme.surfaceHigh
    border.width: menu.opened ? 2 : 1
    border.color: menu.opened ? Theme.primary : modified ? Theme.alpha(Theme.tertiary, 0.7) : Theme.alpha(Theme.outline, 0.35)
    Behavior on color { CAnim {} }
    Behavior on border.color { CAnim {} }

    Txt {
        visible: root.label !== ""
        text: root.label
        x: 14
        y: 7
        font.pixelSize: Theme.size.tiny
        color: menu.opened ? Theme.primary : Theme.surfaceFgDim
    }

    Txt {
        x: 14
        width: parent.width - 52
        y: root.label !== "" ? parent.height - height - 9 : (parent.height - height) / 2
        text: root.value === "" ? "—" : root.value
        mono: root.mono
        color: Theme.surfaceFg
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        icon: "expand_more"
        size: 22
        rotation: menu.opened ? 180 : 0
        color: menu.opened ? Theme.primary : Theme.surfaceFgDim
        Behavior on rotation { Anim { curve: "spatial" } }
    }

    StateLayer {
        radius: root.radius
        onClicked: menu.opened ? menu.close() : menu.open()
    }

    Popup {
        id: menu

        y: root.height + 6
        width: Math.max(root.width, 180)
        height: Math.min(list.contentHeight + 12, 320)
        padding: 6
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            radius: Theme.radius.normal
            color: Theme.surfaceHigh
            border.width: 1
            border.color: Theme.alpha(Theme.outline, 0.2)
        }

        enter: Transition {
            ParallelAnimation {
                Anim { property: "opacity"; from: 0; to: 1; curve: "effects" }
                Anim { property: "scale"; from: 0.92; to: 1; curve: "spatialFast" }
                Anim { property: "height"; from: 0; to: Math.min(list.contentHeight + 12, 320); curve: "emphasizedDecel" }
            }
        }
        exit: Transition {
            ParallelAnimation {
                Anim { property: "opacity"; to: 0; curve: "effects" }
                Anim { property: "scale"; to: 0.96; curve: "emphasizedAccel" }
            }
        }

        contentItem: ListView {
            id: list

            clip: true
            model: root.options
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: opt

                required property int index
                required property string modelData
                readonly property bool selected: modelData === root.value

                width: list.width
                height: 40
                radius: Theme.radius.small
                color: selected ? Theme.secondaryContainer : "transparent"

                Icon {
                    id: check

                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "check"
                    size: 18
                    color: Theme.secondaryContainerFg
                    opacity: opt.selected ? 1 : 0
                    scale: opt.selected ? 1 : 0.3
                }
                Txt {
                    x: 36
                    width: parent.width - 46
                    anchors.verticalCenter: parent.verticalCenter
                    text: opt.modelData === "" ? "—" : opt.modelData
                    mono: root.mono
                    color: opt.selected ? Theme.secondaryContainerFg : Theme.surfaceFg
                }
                StateLayer {
                    onClicked: {
                        root.picked(opt.modelData);
                        menu.close();
                    }
                }
            }
        }
    }
}
