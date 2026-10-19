import QtQuick
import qs.services

// Segmentierte Auswahl mit gleitender, federnder Markierung.
Rectangle {
    id: root

    property var options: []
    property var labels: null         // optionale Anzeigenamen
    property string value: ""
    property real segWidth: 0         // 0 = automatisch

    signal picked(string value)

    readonly property int index: options.indexOf(value)
    readonly property real cellW: segWidth > 0 ? segWidth : Math.max(64, maxLabel + 28)
    property real maxLabel: 0

    implicitWidth: options.length * cellW + 8
    implicitHeight: 40
    radius: height / 2
    color: Theme.surfaceHighest

    function labelFor(i) {
        const raw = labels && labels[i] !== undefined ? labels[i] : options[i];
        return raw === "" ? "—" : raw;
    }

    Rectangle {
        id: pill

        visible: root.index >= 0
        y: 4
        height: root.height - 8
        radius: height / 2
        color: Theme.primary

        property real targetX: 4 + Math.max(0, root.index) * root.cellW
        // elastische Markierung: die vorauslaufende Kante ist schneller als die nachziehende
        property real edgeL: 0
        property real edgeR: 0
        property bool ready: false
        Behavior on edgeL { enabled: pill.ready; Anim { id: leftAnim; curve: "spatial" } }
        Behavior on edgeR { enabled: pill.ready; Anim { id: rightAnim; curve: "spatial" } }
        Component.onCompleted: {
            edgeL = targetX;
            edgeR = targetX + root.cellW;
            ready = true;
        }
        onTargetXChanged: {
            const toRight = targetX > edgeL;
            leftAnim.duration = toRight ? 560 : 360;
            rightAnim.duration = toRight ? 360 : 560;
            edgeL = targetX;
            edgeR = targetX + root.cellW;
        }
        Connections {
            target: root
            function onCellWChanged() {
                pill.ready = false;
                pill.edgeL = pill.targetX;
                pill.edgeR = pill.targetX + root.cellW;
                pill.ready = true;
            }
        }
        x: edgeL
        width: edgeR - edgeL
    }

    Row {
        x: 4
        y: 4

        Repeater {
            model: root.options

            Item {
                id: cell

                required property int index
                required property string modelData
                readonly property bool selected: root.index === index

                width: root.cellW
                height: root.height - 8

                Txt {
                    id: lbl

                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 12)
                    horizontalAlignment: Text.AlignHCenter
                    text: root.labelFor(cell.index)
                    font.pixelSize: Theme.size.small + 1
                    font.weight: cell.selected ? Font.DemiBold : Font.Medium
                    color: cell.selected ? Theme.primaryFg : Theme.surfaceFgDim
                    Component.onCompleted: root.maxLabel = Math.max(root.maxLabel, implicitWidth)
                }

                StateLayer {
                    radius: height / 2
                    tint: cell.selected ? Theme.primaryFg : Theme.surfaceFg
                    onClicked: {
                        root.picked(cell.modelData);
                    }
                }
            }
        }
    }
}
