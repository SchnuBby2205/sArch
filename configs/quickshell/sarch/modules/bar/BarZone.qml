import QtQuick
import qs.components
import qs.services

// Eine Zone der Bar (start / center / end). Im Stil "islands" mit eigener Pille.
Item {
    id: zoneRoot

    property string zone: "start"
    property string ids: ""
    property var host
    property int order: 0

    readonly property var list: ids === "" ? [] : ids.split(",")
    readonly property bool islands: host.style === "islands"
    readonly property real padding: islands ? 5 : 0
    readonly property bool empty: list.length === 0

    width: host.vertical ? host.thick : (empty ? 0 : grid.width + padding * 2)
    height: host.vertical ? (empty ? 0 : grid.height + padding * 2) : host.thick
    Behavior on width { Anim { curve: "spatial" } }
    Behavior on height { Anim { curve: "spatial" } }

    // gestaffeltes Einblenden der Zonen beim Ausfahren
    opacity: host.reveal >= 0.999 ? 1 : 0
    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: zoneRoot.host.shown ? 120 + zoneRoot.order * 90 : 0 }
            Anim { curve: "effects"; duration: 300 }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: zoneRoot.host.cfg.radius
        color: zoneRoot.host.bgColor
        border.width: 1
        border.color: Theme.alpha(Theme.outline, 0.16)
        opacity: zoneRoot.islands && !zoneRoot.empty ? 1 : 0
        Behavior on opacity { Anim { curve: "effects"; duration: 350 } }
    }

    Grid {
        id: grid

        anchors.centerIn: parent
        flow: zoneRoot.host.vertical ? Grid.TopToBottom : Grid.LeftToRight
        rows: zoneRoot.host.vertical ? 100 : 1
        columns: zoneRoot.host.vertical ? 1 : 100
        spacing: 2

        add: Transition {
            ParallelAnimation {
                Anim { property: "scale"; from: 0.3; to: 1; curve: "spatialFast" }
                Anim { property: "opacity"; from: 0; to: 1; curve: "effects" }
            }
        }
        move: Transition {
            Anim { properties: "x,y"; curve: "spatial" }
        }

        Repeater {
            model: zoneRoot.list

            BarModule {
                required property string modelData

                moduleId: modelData
                cfg: zoneRoot.host.cfg
                vertical: zoneRoot.host.vertical
                thick: zoneRoot.host.thick
                screen: zoneRoot.host.screen
                preview: zoneRoot.host.preview
            }
        }
    }
}
