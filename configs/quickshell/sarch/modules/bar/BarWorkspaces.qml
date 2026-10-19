import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.components
import qs.services

// Workspace-Anzeige: belegte Workspaces als Punkte/Zahlen, aktiver als elastische Pille.
// Klick wechselt, Mausrad blättert. Funktioniert horizontal und vertikal.
Item {
    id: root

    property var cfg
    property bool vertical: false
    property real thick: 40
    property var screen: null            // ShellScreen (null = fokussierter Monitor)

    readonly property bool numbers: cfg?.workspaces?.numbers ?? true
    // markiert wird der Workspace, auf dem gerade der Cursor bzw. Fokus ist (monitorübergreifend)
    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1
    // auf anderen Monitoren gerade sichtbare Workspaces (bekommen einen Ring)
    readonly property var visibleIds: {
        const v = {};
        for (const m of (Hyprland.monitors?.values ?? []))
            if (m?.activeWorkspace && m.activeWorkspace.id > 0)
                v[m.activeWorkspace.id] = true;
        return v;
    }
    readonly property var occupied: {
        const o = {};
        for (const w of (Hyprland.workspaces?.values ?? []))
            if (w.id > 0)
                o[w.id] = true;
        return o;
    }
    readonly property int count: {
        let n = Math.max(1, cfg?.workspaces?.count ?? 8);
        for (const k in occupied)
            n = Math.max(n, Number(k));
        return Math.max(n, activeId);
    }

    readonly property real cell: thick - 14          // Grundgröße eines Slots
    readonly property real activeLen: cell * 1.75    // Länge des aktiven Slots

    implicitWidth: vertical ? thick : track.len + 12
    implicitHeight: vertical ? track.len + 12 : thick

    property real wheelAcc: 0
    readonly property string wsScript: `${Quickshell.env("HOME")}/.config/sArch/bin/sarch_workspace.sh`

    function go(id) {
        Quickshell.execDetached([wsScript, String(id)]);
    }

    Item {
        id: track

        readonly property real len: (root.count - 1) * root.cell + root.activeLen
        anchors.centerIn: parent
        width: root.vertical ? root.cell : len
        height: root.vertical ? len : root.cell

        // elastische Pille unter dem aktiven Workspace
        Rectangle {
            id: pill

            readonly property real target: (root.activeId - 1) * root.cell
            property real edgeA: 0
            property real edgeB: 0
            property bool ready: false

            x: root.vertical ? 0 : edgeA
            y: root.vertical ? edgeA : 0
            width: root.vertical ? root.cell : edgeB - edgeA
            height: root.vertical ? edgeB - edgeA : root.cell
            radius: root.cell / 2
            color: Theme.primary

            Behavior on edgeA { enabled: pill.ready; Anim { id: aAnim; curve: "spatial" } }
            Behavior on edgeB { enabled: pill.ready; Anim { id: bAnim; curve: "spatial" } }
            onTargetChanged: {
                const fwd = target > edgeA;
                aAnim.duration = fwd ? 520 : 330;
                bAnim.duration = fwd ? 330 : 520;
                edgeA = target;
                edgeB = target + root.activeLen;
            }
            Component.onCompleted: {
                edgeA = target;
                edgeB = target + root.activeLen;
                ready = true;
            }
        }

        Repeater {
            model: root.count

            Item {
                id: slot

                required property int index
                readonly property int wsId: index + 1
                readonly property bool isActive: wsId === root.activeId
                readonly property bool isOccupied: !!root.occupied[wsId]
                readonly property real pos: index * root.cell + (wsId > root.activeId ? root.activeLen - root.cell : 0)
                readonly property real len: isActive ? root.activeLen : root.cell

                x: root.vertical ? 0 : pos
                y: root.vertical ? pos : 0
                width: root.vertical ? root.cell : len
                height: root.vertical ? len : root.cell
                Behavior on x { Anim { curve: "spatial" } }
                Behavior on y { Anim { curve: "spatial" } }
                Behavior on width { Anim { curve: "spatial" } }
                Behavior on height { Anim { curve: "spatial" } }

                // auf einem anderen Monitor sichtbar -> Ring
                Rectangle {
                    anchors.centerIn: parent
                    width: root.cell - 4
                    height: root.cell - 4
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.primary
                    opacity: !slot.isActive && root.visibleIds[slot.wsId] ? 0.55 : 0
                    scale: opacity > 0 ? 1 : 0.6
                    Behavior on opacity { Anim { curve: "effects" } }
                    Behavior on scale { Anim { curve: "spatialFast" } }
                }

                // Punkt (ohne Zahlen)
                Rectangle {
                    visible: !root.numbers
                    anchors.centerIn: parent
                    width: slot.isActive ? root.cell * 0.34 : slot.isOccupied ? root.cell * 0.34 : root.cell * 0.2
                    height: width
                    radius: width / 2
                    color: slot.isActive ? Theme.primaryFg : Theme.surfaceFg
                    opacity: slot.isActive ? 1 : slot.isOccupied ? 0.75 : 0.28
                    Behavior on width { Anim { curve: "spatialFast" } }
                    Behavior on opacity { Anim { curve: "effects" } }
                }

                // Zahl
                Txt {
                    visible: root.numbers
                    anchors.centerIn: parent
                    text: slot.wsId
                    mono: true
                    font.pixelSize: Math.round(root.cell * 0.46)
                    font.weight: slot.isActive || slot.isOccupied ? Font.Bold : Font.Normal
                    color: slot.isActive ? Theme.primaryFg : Theme.surfaceFg
                    opacity: slot.isActive ? 1 : slot.isOccupied ? 0.9 : 0.35
                    scale: wsArea.containsMouse && !slot.isActive ? 1.2 : 1
                    Behavior on scale { Anim { curve: "spatialFast" } }
                    Behavior on opacity { Anim { curve: "effects" } }
                }

                // belegter, aber nicht aktiver Workspace: kleiner Akzent-Strich
                Rectangle {
                    visible: root.numbers && slot.isOccupied && !slot.isActive
                    width: root.vertical ? 3 : root.cell * 0.3
                    height: root.vertical ? root.cell * 0.3 : 3
                    radius: 1.5
                    color: Theme.primary
                    opacity: 0.7
                    x: root.vertical ? parent.width - width : (parent.width - width) / 2
                    y: root.vertical ? (parent.height - height) / 2 : parent.height - height
                }

                MouseArea {
                    id: wsArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.go(slot.wsId)
                }
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: e => {
            // Trackpads liefern viele kleine Schritte -> sammeln, erst ab einer Raste wechseln
            root.wheelAcc += e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x;
            if (Math.abs(root.wheelAcc) >= 120) {
                root.go(root.wheelAcc > 0 ? "e-1" : "e+1");
                root.wheelAcc = 0;
            }
        }
    }
}
