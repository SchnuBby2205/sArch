import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components
import qs.services

// Vorschau eines Workspaces: Miniatur des Monitors mit allen Fenstern an ihrer Position.
// Live-Bild per Screencopy; ohne Bild (z. B. Fenster minimiert) App-Icon + Titel.
Item {
    id: root

    property int wsId: 1
    property bool shown: false
    signal picked(int id)

    readonly property var ws: (Hyprland.workspaces?.values ?? []).find(w => w.id === wsId) ?? null
    readonly property var mon: ws?.monitor ?? Hyprland.focusedMonitor
    readonly property real scaleF: mon?.scale > 0 ? mon.scale : 1
    readonly property real monX: mon?.x ?? 0
    readonly property real monY: mon?.y ?? 0
    readonly property real monW: Math.max(1, (mon?.width ?? 1920) / scaleF)
    readonly property real monH: Math.max(1, (mon?.height ?? 1080) / scaleF)
    readonly property var wins: (Hyprland.toplevels?.values ?? []).filter(t => t?.workspace?.id === wsId)

    readonly property real stageW: 340
    readonly property real stageH: Math.round(stageW * monH / monW)
    readonly property real k: stageW / monW

    implicitWidth: stageW + 24
    implicitHeight: header.height + stageH + 34

    onShownChanged: if (shown && Hyprland.refreshToplevels)
        Hyprland.refreshToplevels()

    // Auf-/Zuklappen
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.94
    Behavior on opacity { Anim { curve: "effects"; duration: root.shown ? 220 : 120 } }
    Behavior on scale { Anim { curve: root.shown ? "spatial" : "emphasizedAccel"; duration: root.shown ? 420 : 140 } }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.large
        color: Theme.alpha(Theme.surfaceContainer, 0.97)
        border.width: 1
        border.color: Theme.alpha(Theme.outline, 0.24)
    }

    Row {
        id: header

        x: 14
        y: 10
        height: 26
        spacing: 8

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 8
            color: Theme.primary
            Txt {
                anchors.centerIn: parent
                text: root.wsId
                font.pixelSize: Theme.size.small
                font.weight: Font.Bold
                color: Theme.primaryFg
            }
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.wins.length === 0 ? "Leer" : root.wins.length === 1 ? "1 Fenster" : `${root.wins.length} Fenster`
            font.pixelSize: Theme.size.small + 1
            font.weight: Font.DemiBold
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!root.mon?.name
            text: `· ${root.mon?.name ?? ""}`
            font.pixelSize: Theme.size.small
            color: Theme.surfaceFgDim
        }
    }

    // Monitor-Miniatur
    Rectangle {
        id: stage

        x: 12
        y: header.y + header.height + 10
        width: root.stageW
        height: root.stageH
        radius: Theme.radius.normal
        color: Theme.alpha(Theme.surface, 0.9)
        clip: true

        // Wallpaper als Hintergrund
        RoundedImage {
            anchors.fill: parent
            radius: parent.radius
            source: Theme.wallpaper !== "" ? "file://" + Theme.wallpaper : ""
            sourceSize.width: 480
            opacity: 0.55
        }

        Repeater {
            model: root.wins

            Rectangle {
                id: win

                required property var modelData
                required property int index
                readonly property var ipc: modelData?.lastIpcObject ?? ({})
                readonly property var at: ipc.at ?? [root.monX + 40 + index * 30, root.monY + 40 + index * 30]
                readonly property var sz: ipc.size ?? [root.monW * 0.5, root.monH * 0.5]
                readonly property string cls: ipc.class ?? ipc.initialClass ?? ""
                readonly property var entry: cls !== "" && DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(cls) : null

                x: Math.max(0, (at[0] - root.monX) * root.k)
                y: Math.max(0, (at[1] - root.monY) * root.k)
                width: Math.max(18, sz[0] * root.k)
                height: Math.max(14, sz[1] * root.k)
                radius: 6
                color: Theme.alpha(Theme.surfaceHigh, 0.95)
                border.width: winArea.containsMouse ? 2 : 1
                border.color: winArea.containsMouse ? Theme.primary : Theme.alpha(Theme.outline, 0.35)
                clip: true
                z: ipc.floating ? 2 : 1

                // gestaffelt einblenden
                opacity: 0
                scale: 0.9
                Component.onCompleted: popIn.start()
                ParallelAnimation {
                    id: popIn
                    SequentialAnimation {
                        PauseAnimation { duration: win.index * 40 }
                        Anim { target: win; property: "opacity"; to: 1; curve: "effects"; duration: 200 }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: win.index * 40 }
                        Anim { target: win; property: "scale"; to: 1; curve: "spatial" }
                    }
                }

                // Ersatz: Icon + Titel
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    spacing: 3
                    visible: !shot.hasContent

                    AppIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        entry: win.entry ?? { name: win.cls || win.modelData?.title || "?", icon: win.cls.toLowerCase() }
                        size: Math.min(32, Math.max(14, win.height * 0.4))
                    }
                    Txt {
                        width: parent.width
                        visible: win.height > 46
                        horizontalAlignment: Text.AlignHCenter
                        text: win.modelData?.title ?? ""
                        font.pixelSize: 10
                        color: Theme.surfaceFgDim
                        elide: Text.ElideRight
                    }
                }

                // Live-Bild des Fensters
                ScreencopyView {
                    id: shot

                    anchors.fill: parent
                    anchors.margins: 1
                    captureSource: root.shown ? (win.modelData?.wayland ?? null) : null
                    live: root.shown
                }

                // Titel-Leiste beim Hovern
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 18
                    color: Theme.alpha(Theme.surface, 0.85)
                    visible: shot.hasContent && winArea.containsMouse
                    Txt {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        text: win.modelData?.title ?? ""
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: winArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(root.wsId)
                }
            }
        }

        // leerer Workspace
        Column {
            anchors.centerIn: parent
            visible: root.wins.length === 0
            spacing: 6
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: "check_box_outline_blank"
                size: 30
                color: Theme.surfaceFgDim
            }
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Keine Fenster"
                font.pixelSize: Theme.size.small
                color: Theme.surfaceFgDim
            }
        }
    }
}
