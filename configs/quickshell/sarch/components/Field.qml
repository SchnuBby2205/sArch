import QtQuick
import qs.services

// Eingabefeld mit schwebendem Label, animierter Fokus-Kontur und Änderungsmarker.
Rectangle {
    id: root

    property alias text: input.text
    property string label: ""
    property string placeholder: ""
    property string icon: ""
    property bool mono: false
    property bool modified: false
    property bool compact: false
    property alias input: input
    property int fontSize: Theme.size.body
    property var keyHandler: null   // function(event) – z.B. Pfeiltasten an eine Liste weiterreichen

    signal edited
    signal accepted

    readonly property bool raised: input.activeFocus || input.text.length > 0 || compact

    implicitWidth: 240
    implicitHeight: compact ? 40 : 56
    radius: Theme.radius.small + 2
    color: input.activeFocus ? Theme.surfaceHighest : Theme.surfaceHigh
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? Theme.primary : modified ? Theme.alpha(Theme.tertiary, 0.7) : Theme.alpha(Theme.outline, 0.35)

    Behavior on color { CAnim {} }
    Behavior on border.color { CAnim {} }

    function forceFocus() {
        input.forceActiveFocus();
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onPressed: e => {
            input.forceActiveFocus();
            e.accepted = false;
        }
    }

    Icon {
        id: leadIcon

        visible: root.icon !== ""
        icon: root.icon
        size: 20
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: input.activeFocus ? Theme.primary : Theme.surfaceFgDim
        fill: input.activeFocus ? 1 : 0
    }

    Txt {
        id: floating

        visible: root.label !== "" && !root.compact
        text: root.label
        x: leadIcon.visible ? 42 : 14
        y: root.raised ? 7 : (root.height - height) / 2
        font.pixelSize: root.raised ? Theme.size.tiny : Theme.size.body
        color: input.activeFocus ? Theme.primary : Theme.surfaceFgDim

        Behavior on y { Anim { curve: "spatialFast" } }
        Behavior on font.pixelSize { Anim { curve: "standard" } }
    }

    TextInput {
        id: input

        anchors.left: parent.left
        anchors.right: modDot.left
        anchors.leftMargin: leadIcon.visible ? 42 : 14
        anchors.rightMargin: 8
        y: root.compact || root.label === "" ? (root.height - height) / 2 : root.height - height - 9
        color: Theme.surfaceFg
        selectionColor: Theme.alpha(Theme.primary, 0.4)
        selectedTextColor: Theme.surfaceFg
        // Oberflächen-Schrift auch in Wert-/Code-Feldern (mono = nur gleich breite Ziffern)
        font.family: Theme.sans
        font.features: root.mono ? { "tnum": 1 } : ({})
        font.pixelSize: root.fontSize
        clip: true
        selectByMouse: true
        activeFocusOnTab: true          // Tab / Shift+Tab: nächstes / vorheriges Feld
        onTextEdited: root.edited()
        Keys.onPressed: e => {
            if (root.keyHandler)
                root.keyHandler(e);
            else
                e.accepted = false;
        }
        onAccepted: root.accepted()
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder
            visible: input.text.length === 0 && (root.raised || root.label === "")
            color: Theme.alpha(Theme.surfaceFgDim, 0.6)
            font: input.font
        }
    }

    Rectangle {
        id: modDot

        width: root.modified ? 8 : 0
        height: 8
        radius: 4
        color: Theme.tertiary
        anchors.right: parent.right
        anchors.rightMargin: root.modified ? 12 : 4
        anchors.verticalCenter: parent.verticalCenter
        Behavior on width { Anim { curve: "spatialFast" } }
    }
}
