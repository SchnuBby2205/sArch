import QtQuick
import qs.services

// Material-3-Expressive-Slider: dicke Spur, schmaler Griff mit Lücke, Werteblase beim Ziehen.
Item {
    id: root

    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property string suffix: ""
    readonly property bool dragging: area.pressed

    signal moved(real value)

    implicitWidth: 300
    implicitHeight: 44
    activeFocusOnTab: true

    readonly property real range: Math.max(0.0001, to - from)
    property real pos: (value - from) / range
    Behavior on pos {
        enabled: !area.pressed
        Anim { curve: "spatial" }
    }

    readonly property real handleX: 6 + pos * (width - 12)
    readonly property int decimals: stepSize > 0 && stepSize < 1 ? Math.min(3, String(stepSize).split(".")[1]?.length ?? 1) : 0

    function snap(v) {
        if (stepSize > 0)
            v = Math.round((v - from) / stepSize) * stepSize + from;
        return Math.max(from, Math.min(to, Number(v.toFixed(4))));
    }
    function setFromX(x) {
        const v = snap(from + Math.max(0, Math.min(1, (x - 6) / (width - 12))) * range);
        if (v !== value) {
            value = v;
            moved(v);
        }
    }

    Keys.onLeftPressed: { value = snap(value - stepSize); moved(value); }
    Keys.onRightPressed: { value = snap(value + stepSize); moved(value); }

    // aktive Spur
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: Math.max(0, root.handleX - 6)
        height: 16
        radius: 8
        topRightRadius: 3
        bottomRightRadius: 3
        color: Theme.primary
    }
    // inaktive Spur
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.handleX + 6
        width: Math.max(0, root.width - x)
        height: 16
        radius: 8
        topLeftRadius: 3
        bottomLeftRadius: 3
        color: Theme.secondaryContainer

        Rectangle {
            width: 4
            height: 4
            radius: 2
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.primary
            visible: parent.width > 14
        }
    }

    // Griff
    Rectangle {
        id: handle

        x: root.handleX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: area.pressed ? 2 : 4
        height: area.pressed ? 40 : 34
        radius: 2
        color: Theme.primary
        Behavior on width { Anim { curve: "spatialFast" } }
        Behavior on height { Anim { curve: "spatialFast" } }
    }

    // Werteblase
    Rectangle {
        id: bubble

        readonly property bool shown: area.pressed || root.activeFocus
        x: Math.max(0, Math.min(root.width - width, root.handleX - width / 2))
        y: -height - 4
        width: Math.max(44, bubbleText.implicitWidth + 20)
        height: 32
        radius: 16
        color: Theme.surfaceHighest
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.5
        transformOrigin: Item.Bottom
        Behavior on opacity { Anim { curve: "effects" } }
        Behavior on scale { Anim { curve: "spatialFast" } }

        Txt {
            id: bubbleText

            anchors.centerIn: parent
            text: root.value.toFixed(root.decimals) + root.suffix
            mono: true
            font.weight: Font.DemiBold
            color: Theme.surfaceFg
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: e => {
            root.forceActiveFocus();
            root.setFromX(e.x);
        }
        onPositionChanged: e => {
            if (pressed)
                root.setFromX(e.x);
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: e => {
            const d = e.angleDelta.y > 0 ? root.stepSize : -root.stepSize;
            root.value = root.snap(root.value + d);
            root.moved(root.value);
        }
    }
}
