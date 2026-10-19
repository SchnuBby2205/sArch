import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.components
import qs.services

// Lautstärke: Klick -> pavucontrol, Mausrad -> lauter/leiser, Mittelklick -> stumm
Item {
    id: root

    property var cfg
    property bool vertical: false
    property real thick: 40

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property string volScript: `${Quickshell.env("HOME")}/.config/sArch/bin/sarch_change_volume.sh`

    implicitWidth: btn.implicitWidth
    implicitHeight: btn.implicitHeight

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    BarButton {
        id: btn

        thick: root.thick
        vertical: root.vertical
        icon: root.muted || root.volume <= 0.001 ? "volume_off" : root.volume < 0.35 ? "volume_mute" : root.volume < 0.7 ? "volume_down" : "volume_up"
        label: (root.cfg?.audio?.percent ?? true) && root.sink ? `${Math.round(root.volume * 100)}%` : ""
        accent: root.muted ? Theme.error : Theme.primary
        active: root.muted
        onClicked: Quickshell.execDetached(["pavucontrol"])
        onMiddleClicked: Quickshell.execDetached([root.volScript, "toggle"])
        onWheel: d => Quickshell.execDetached([root.volScript, d > 0 ? "5%+" : "5%-", "unmute"])
    }

    // Pegel als feine Linie unter dem Icon
    Rectangle {
        visible: !!root.sink
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.vertical ? 2 : 6
        x: root.vertical ? 0 : 10
        width: (root.vertical ? root.thick - 18 : btn.implicitWidth - 20) * Math.min(1, root.volume)
        height: 2
        radius: 1
        color: root.muted ? Theme.error : Theme.primary
        opacity: 0.6
        Behavior on width { Anim { curve: "spatialFast" } }
    }
}
