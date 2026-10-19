import QtQuick
import QtQuick.Controls
import Quickshell
import qs.components
import qs.services

// App-Launcher: Glas-Panel mit großer Suche, "Zuletzt verwendet", animiertes Raster.
// Tippen sucht sofort, Pfeile bewegen die Auswahl, Enter startet, Esc schließt.
Item {
    id: root

    property bool open: false
    property string query: ""
    property bool animateIn: true

    signal closed

    readonly property var results: Apps.search(query)
    readonly property bool showRecent: query.trim() === "" && Apps.recent.length > 0
    readonly property int columns: 6

    function show() {
        query = "";
        search.text = "";
        animateIn = true;
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
        open = true;
        Qt.callLater(() => search.forceFocus());
    }
    function requestClose() {
        open = false;
    }
    function launch(e) {
        if (!e)
            return;
        Apps.launch(e);
        open = false;
    }
    function move(dx, dy) {
        const n = grid.count;
        if (n === 0)
            return;
        let i = grid.currentIndex + dx + dy * columns;
        grid.currentIndex = Math.max(0, Math.min(n - 1, i));
    }

    onQueryChanged: {
        animateIn = false;
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.38)
        opacity: root.open ? 1 : 0
        Behavior on opacity { Anim { curve: "standard"; duration: root.open ? 380 : 240 } }

        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.requestClose()
        }
    }

    // ── Panel ──
    Item {
        id: panel

        width: Math.min(root.width - 80, root.columns * 118 + 56)
        height: Math.min(root.height - 120, 640)
        anchors.horizontalCenter: parent.horizontalCenter
        y: (root.height - height) / 2 - 30 + (root.open ? 0 : 60)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.92

        Behavior on y { Anim { curve: root.open ? "spatialSlow" : "emphasizedAccel"; duration: root.open ? 650 : 240 } }
        Behavior on scale { Anim { curve: root.open ? "spatialSlow" : "emphasizedAccel"; duration: root.open ? 650 : 240 } }
        Behavior on opacity {
            SequentialAnimation {
                Anim { curve: root.open ? "effects" : "emphasizedAccel"; duration: root.open ? 260 : 240 }
                ScriptAction { script: if (!root.open) root.closed() }
            }
        }

        MouseArea {
            anchors.fill: parent
        } // Klicks nicht zum Scrim

        GlassPanel {
            anchors.fill: parent
            tint: 0.82
        }

        // Suche
        Rectangle {
            id: searchBox

            x: 20
            y: 20
            width: parent.width - 40
            height: 60
            radius: 30
            color: Theme.alpha(Theme.surfaceHighest, 0.9)
            border.width: 2
            border.color: search.input.activeFocus ? Theme.primary : "transparent"
            Behavior on border.color { CAnim {} }

            Icon {
                id: searchIcon

                x: 22
                anchors.verticalCenter: parent.verticalCenter
                icon: root.query === "" ? "apps" : "search"
                size: 26
                fill: 1
                color: Theme.primary
                rotation: root.query === "" ? 0 : 90
                Behavior on rotation { Anim { curve: "spatial" } }
            }

            Field {
                id: search

                anchors.left: searchIcon.right
                anchors.leftMargin: 8
                anchors.right: countChip.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                color: "transparent"
                border.width: 0
                placeholder: Backend.t("qs_ln_search", "Apps durchsuchen …")
                fontSize: Theme.size.title
                onEdited: root.query = text
                onAccepted: root.launch(root.results[grid.currentIndex])

                keyHandler: e => {
                    switch (e.key) {
                    case Qt.Key_Escape: root.requestClose(); break;
                    case Qt.Key_Down: root.move(0, 1); break;
                    case Qt.Key_Up: root.move(0, -1); break;
                    case Qt.Key_Tab: root.move(1, 0); break;
                    case Qt.Key_Backtab: root.move(-1, 0); break;
                    case Qt.Key_Right:
                        if (search.input.cursorPosition < search.text.length) {
                            e.accepted = false;
                            return;
                        }
                        root.move(1, 0);
                        break;
                    case Qt.Key_Left:
                        if (search.input.cursorPosition > 0) {
                            e.accepted = false;
                            return;
                        }
                        root.move(-1, 0);
                        break;
                    case Qt.Key_PageDown: root.move(0, 3); break;
                    case Qt.Key_PageUp: root.move(0, -3); break;
                    default: e.accepted = false; return;
                    }
                    e.accepted = true;
                }
            }

            Rectangle {
                id: countChip

                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: cnt.implicitWidth + 22
                height: 32
                radius: 16
                color: Theme.alpha(Theme.primary, 0.15)

                Txt {
                    id: cnt

                    anchors.centerIn: parent
                    text: root.results.length
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }
        }

        // Zuletzt verwendet
        Item {
            id: recentBox

            x: 20
            y: searchBox.y + searchBox.height + 16
            width: parent.width - 40
            height: root.showRecent ? 92 : 0
            clip: true
            opacity: root.showRecent ? 1 : 0
            Behavior on height { Anim { curve: "spatial" } }
            Behavior on opacity { Anim { curve: "effects" } }

            Txt {
                x: 6
                text: Backend.t("qs_ln_recent", "Zuletzt verwendet")
                font.pixelSize: Theme.size.small
                font.weight: Font.DemiBold
                color: Theme.surfaceFgDim
            }
            Row {
                y: 24
                spacing: 8

                Repeater {
                    model: root.showRecent ? Apps.recent : []

                    Rectangle {
                        id: chip

                        required property var modelData
                        required property int index

                        width: chipRow.implicitWidth + 26
                        height: 52
                        radius: 26
                        color: chipArea.containsMouse ? Theme.secondaryContainer : Theme.alpha(Theme.surfaceHigh, 0.75)
                        Behavior on color { CAnim {} }
                        scale: 0
                        Component.onCompleted: chipIn.start()
                        SequentialAnimation {
                            id: chipIn
                            PauseAnimation { duration: 120 + chip.index * 45 }
                            Anim { target: chip; property: "scale"; to: 1; curve: "spatialFast" }
                        }

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: 10

                            AppIcon {
                                entry: chip.modelData
                                size: 30
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Txt {
                                text: chip.modelData.name
                                font.weight: Font.Medium
                                width: Math.min(implicitWidth, 120)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        StateLayer {
                            id: chipArea

                            radius: 26
                            onClicked: root.launch(chip.modelData)
                        }
                    }
                }
            }
        }

        // Raster
        GridView {
            id: grid

            x: 20
            y: recentBox.y + recentBox.height + (root.showRecent ? 6 : 0)
            width: parent.width - 40
            height: footer.y - y - 8
            cellWidth: Math.floor(width / root.columns)
            cellHeight: 124
            clip: true
            model: root.results
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            highlightFollowsCurrentItem: false
            Behavior on y { Anim { curve: "spatial" } }

            ScrollBar.vertical: ScrollBar {
                id: sb

                contentItem: Rectangle {
                    implicitWidth: 5
                    radius: 3
                    color: Theme.alpha(Theme.surfaceFgDim, sb.pressed ? 0.6 : 0.3)
                }
                background: null
            }

            // federnde Auswahl
            Rectangle {
                id: hl

                readonly property Item cur: grid.currentItem
                z: -1
                x: cur ? cur.x + 6 : 0
                y: cur ? cur.y + 4 : 0
                width: grid.cellWidth - 12
                height: grid.cellHeight - 8
                radius: Theme.radius.large
                color: Theme.alpha(Theme.primary, 0.18)
                border.width: 2
                border.color: Theme.alpha(Theme.primary, 0.6)
                visible: grid.count > 0
                Behavior on x { Anim { curve: "spatial"; duration: 380 } }
                Behavior on y { Anim { curve: "spatial"; duration: 380 } }
            }

            delegate: Item {
                id: tile

                required property var modelData
                required property int index
                readonly property bool sel: GridView.isCurrentItem

                width: grid.cellWidth
                height: grid.cellHeight

                opacity: root.animateIn && index < 30 ? 0 : 1
                property real dy: root.animateIn && index < 30 ? 24 : 0
                transform: Translate { y: tile.dy }
                Component.onCompleted: if (root.animateIn && index < 30)
                    tileIn.start()
                SequentialAnimation {
                    id: tileIn

                    PauseAnimation { duration: 90 + tile.index * 16 }
                    ParallelAnimation {
                        Anim { target: tile; property: "opacity"; to: 1; curve: "effects"; duration: 260 }
                        Anim { target: tile; property: "dy"; to: 0; curve: "spatialSlow" }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    scale: tileArea.pressed ? 0.9 : tile.sel ? 1.08 : 1
                    Behavior on scale { Anim { curve: "spatialFast" } }

                    AppIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        entry: tile.modelData
                        size: 52
                    }
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: grid.cellWidth - 18
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.name
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: Theme.size.small + 1
                        font.weight: tile.sel ? Font.DemiBold : Font.Normal
                        color: tile.sel ? Theme.surfaceFg : Theme.surfaceFgDim
                    }
                }

                MouseArea {
                    id: tileArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: grid.currentIndex = tile.index
                    onClicked: root.launch(tile.modelData)
                }
            }

            // keine Treffer
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: grid.count === 0

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: "search_off"
                    size: 56
                    color: Theme.alpha(Theme.surfaceFgDim, 0.5)
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Backend.t("qs_no_results", "Nichts gefunden für „{q}“", { q: root.query })
                    color: Theme.surfaceFgDim
                }
            }
        }

        // Fußzeile
        Item {
            id: footer

            x: 24
            width: parent.width - 48
            height: 40
            y: parent.height - height - 10

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Keycap { label: "↵"; anchors.verticalCenter: parent.verticalCenter }
                Txt { text: Backend.t("qs_ln_start", "starten"); color: Theme.surfaceFgDim; font.pixelSize: Theme.size.small; anchors.verticalCenter: parent.verticalCenter; rightPadding: 12 }
                Keycap { label: "↑↓←→"; anchors.verticalCenter: parent.verticalCenter }
                Txt { text: Backend.t("qs_ln_move", "wählen"); color: Theme.surfaceFgDim; font.pixelSize: Theme.size.small; anchors.verticalCenter: parent.verticalCenter; rightPadding: 12 }
                Keycap { label: "Esc"; anchors.verticalCenter: parent.verticalCenter }
                Txt { text: Backend.t("qs_ln_close", "schließen"); color: Theme.surfaceFgDim; font.pixelSize: Theme.size.small; anchors.verticalCenter: parent.verticalCenter }
            }

            Txt {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width / 2
                horizontalAlignment: Text.AlignRight
                text: root.results[grid.currentIndex]?.comment || root.results[grid.currentIndex]?.genericName || ""
                font.pixelSize: Theme.size.small
                color: Theme.surfaceFgDim
            }
        }
    }
}
