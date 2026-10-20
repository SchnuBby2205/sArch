import QtQuick
import qs.services

// Ein Formularfeld aus einer Felddefinition {key,label,type,options,value}
// text -> Field, dropdown mit ≤4 kurzen Optionen -> Segmented, sonst -> Select
Item {
    id: root

    property var def: ({})
    property string value: ""
    property string original: ""
    property bool mono: false
    property bool showModified: true
    readonly property bool isModified: showModified && value !== original

    signal changed(string value)
    signal submitted

    function forceFocus() {
        const f = ld.item;
        if (f && f.forceFocus)
            f.forceFocus();
    }

    readonly property var opts: {
        const o = (def.options || []).slice();
        if (root.original !== "" && o.length && o.indexOf(root.original) < 0)
            o.unshift(root.original);
        return o;
    }
    readonly property bool isChoice: def.type === "dropdown" && opts.length > 0
    readonly property bool segmented: isChoice && opts.length <= 4 && opts.join("").length <= 26

    implicitHeight: segmented ? 64 : 56

    Loader {
        id: ld

        anchors.fill: parent
        sourceComponent: root.segmented ? segComp : root.isChoice ? selComp : textComp
    }

    Component {
        id: textComp

        Field {
            id: tf

            label: root.def.label || root.def.key
            text: root.value
            mono: root.mono
            modified: root.isModified
            // Wert nicht selbst setzen: der Aufrufer übernimmt ihn und gibt ihn über die Bindung
            // zurück – so kommt auch "Zurücksetzen" im Feld an
            onEdited: root.changed(text)
            onAccepted: root.submitted()
            Connections {
                target: root
                function onValueChanged() {
                    if (tf.text !== root.value)
                        tf.text = root.value;
                }
            }
        }
    }

    Component {
        id: selComp

        Select {
            label: root.def.label || root.def.key
            options: root.opts
            value: root.value
            mono: root.mono
            modified: root.isModified
            onPicked: v => root.changed(v)
        }
    }

    Component {
        id: segComp

        Item {
            Txt {
                id: segLabel

                text: root.def.label || root.def.key
                font.pixelSize: Theme.size.tiny
                color: Theme.surfaceFgDim
                x: 4
            }
            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: Theme.tertiary
                anchors.left: segLabel.right
                anchors.leftMargin: 6
                anchors.verticalCenter: segLabel.verticalCenter
                visible: root.isModified
            }
            Segmented {
                anchors.bottom: parent.bottom
                options: root.opts
                value: root.value
                segWidth: Math.max(56, Math.min(110, (parent.width - 8) / Math.max(1, root.opts.length)))
                onPicked: v => root.changed(v)
            }
        }
    }
}
