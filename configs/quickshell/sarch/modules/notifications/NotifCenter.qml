import QtQuick
import qs.components
import qs.services

// Benachrichtigungszentrale: Verlauf, "Nicht stören", alles löschen.
// Gleitet von rechts herein; Klick daneben oder Esc schließt.
Item {
    id: root

    property bool open: false
    signal closed

    function show() {
        open = true;
        Notifs.centerOpen = true;
        forceActiveFocus();
    }
    function requestClose() {
        open = false;
        Notifs.centerOpen = false;
    }

    property real t: open ? 1 : 0
    Behavior on t { Anim { curve: root.open ? "spatial" : "emphasizedAccel"; duration: root.open ? 520 : 240 } }
    onTChanged: if (t === 0 && !open)
        closed()

    focus: true
    Keys.onEscapePressed: requestClose()

    // Klick daneben schließt
    MouseArea {
        anchors.fill: parent
        onClicked: root.requestClose()
    }
    // kein Abdunkeln des Desktops – die Zentrale schwebt nur rechts darüber

    Item {
        id: panel

        readonly property real w: Math.min(440, root.width - 24)
        width: w
        height: root.height - 24
        y: 12
        x: root.width - 12 - w + (1 - root.t) * (w + 40)
        opacity: Math.min(1, root.t * 1.6)

        MouseArea {
            anchors.fill: parent        // Klicks im Panel nicht durchreichen
        }

        GlassPanel {
            anchors.fill: parent
            radius: Theme.radius.xl
            tint: 0.86
        }

        // ── Kopf ──
        Item {
            id: head

            x: 20
            y: 18
            width: parent.width - 40
            height: 52

            Rectangle {
                id: bubble

                width: 44
                height: 44
                radius: 15
                anchors.verticalCenter: parent.verticalCenter
                color: Notifs.dnd ? Theme.tertiaryContainer : Theme.primaryContainer

                Icon {
                    anchors.centerIn: parent
                    icon: Notifs.dnd ? "notifications_paused" : "notifications"
                    size: 24
                    fill: 1
                    color: Notifs.dnd ? Theme.tertiaryContainerFg : Theme.primaryContainerFg
                    rotation: bellWiggle.r
                    QtObject {
                        id: bellWiggle
                        property real r: 0
                    }
                    SequentialAnimation {
                        running: root.open && Notifs.historyModel.count > 0
                        NumberAnimation { target: bellWiggle; property: "r"; to: 16; duration: 90 }
                        NumberAnimation { target: bellWiggle; property: "r"; to: -12; duration: 110 }
                        NumberAnimation { target: bellWiggle; property: "r"; to: 7; duration: 100 }
                        NumberAnimation { target: bellWiggle; property: "r"; to: 0; duration: 140; easing.type: Easing.OutBack }
                    }
                }
            }
            Column {
                anchors.left: bubble.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Txt {
                    text: Backend.tr("Benachrichtigungen")
                    font.pixelSize: Theme.size.title
                    font.weight: Font.DemiBold
                }
                Txt {
                    text: Notifs.dnd ? Backend.tr("Nicht stören ist an") : Notifs.historyModel.count === 0 ? Backend.tr("Alles erledigt") : Backend.tr("{n} im Verlauf", { n: Notifs.historyModel.count })
                    font.pixelSize: Theme.size.small
                    color: Notifs.dnd ? Theme.tertiary : Theme.surfaceFgDim
                }
            }
            IconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                size: 36
                onClicked: root.requestClose()
            }
        }

        // ── Schalter-Zeile ──
        Row {
            id: tools

            x: 20
            y: head.y + head.height + 12
            spacing: 8

            // Nicht stören
            Rectangle {
                id: dndChip

                width: dndRow.implicitWidth + 28
                height: 38
                radius: 19
                color: Notifs.dnd ? Theme.tertiary : Theme.alpha(Theme.surfaceHighest, 0.9)
                Behavior on color { CAnim {} }

                Row {
                    id: dndRow

                    anchors.centerIn: parent
                    spacing: 8
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: Notifs.dnd ? "do_not_disturb_on" : "do_not_disturb_off"
                        size: 20
                        fill: Notifs.dnd ? 1 : 0
                        color: Notifs.dnd ? Theme.surface : Theme.surfaceFg
                    }
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Backend.tr("Nicht stören")
                        font.weight: Font.DemiBold
                        font.pixelSize: Theme.size.small + 1
                        color: Notifs.dnd ? Theme.surface : Theme.surfaceFg
                    }
                }
                StateLayer {
                    radius: 19
                    tint: Notifs.dnd ? Theme.surface : Theme.surfaceFg
                    onClicked: Notifs.setDnd(!Notifs.dnd)
                }
            }

            // Alle löschen
            Rectangle {
                width: clearRow.implicitWidth + 28
                height: 38
                radius: 19
                color: Theme.alpha(Theme.error, clearArea.containsMouse ? 0.2 : 0.1)
                opacity: Notifs.historyModel.count > 0 ? 1 : 0.4
                Behavior on color { CAnim {} }

                Row {
                    id: clearRow

                    anchors.centerIn: parent
                    spacing: 8
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "clear_all"
                        size: 20
                        color: Theme.error
                    }
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Backend.tr("Alle löschen")
                        font.weight: Font.DemiBold
                        font.pixelSize: Theme.size.small + 1
                        color: Theme.error
                    }
                }
                StateLayer {
                    id: clearArea

                    radius: 19
                    tint: Theme.error
                    disabled: Notifs.historyModel.count === 0
                    onClicked: clearAnim.start()
                }
            }
        }

        // ── Verlauf ──
        ListView {
            id: list

            x: 16
            y: tools.y + tools.height + 16
            width: parent.width - 32
            height: parent.height - y - 16
            clip: true
            spacing: 10
            model: Notifs.historyModel
            boundsBehavior: Flickable.StopAtBounds

            // "Alle löschen": Karten fliegen nacheinander raus
            property real clearT: 0
            SequentialAnimation {
                id: clearAnim
                Anim { target: list; property: "clearT"; from: 0; to: 1; curve: "emphasizedAccel"; duration: 380 }
                // Liste leeren, Verschiebung aber erst zurücksetzen, wenn die Karten weg sind –
                // sonst springen sie für die Dauer der Entfernen-Animation an ihren Platz zurück
                ScriptAction { script: { list.clearing = true; Notifs.clearHistory(); clearReset.restart(); } }
            }
            property bool clearing: false
            Timer {
                id: clearReset

                interval: 450
                onTriggered: {
                    list.clearT = 0;
                    list.clearing = false;
                }
            }

            add: Transition {
                Anim { property: "opacity"; from: 0; to: 1; curve: "effects"; duration: 260 }
                Anim { property: "x"; from: 60; to: 0; curve: "spatial" }
            }
            remove: Transition {
                enabled: !list.clearing
                ParallelAnimation {
                    Anim { property: "x"; to: list.width; curve: "emphasizedAccel"; duration: 240 }
                    Anim { property: "opacity"; to: 0; curve: "effects"; duration: 200 }
                }
            }
            displaced: Transition {
                Anim { property: "y"; curve: "spatial" }
            }

            delegate: NotifCard {
                id: hc

                required property int index
                required property var model

                app: model.app
                appIcon: model.appIcon
                summary: model.summary
                body: model.body
                image: model.image
                urgency: model.urgency
                time: model.time
                width: list.width
                compact: true
                // beim Öffnen gestaffelt einblenden, beim Löschen gestaffelt hinaus
                property real enter: 0
                opacity: enter * (1 - Math.min(1, Math.max(0, list.clearT * 1.6 - index * 0.08)))
                transform: Translate {
                    x: (1 - hc.enter) * 40 + Math.max(0, list.clearT * 1.6 - hc.index * 0.08) * list.width
                }
                Component.onCompleted: enterAnim.start()
                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { duration: Math.max(0, Math.min(hc.index, 8)) * 45 }
                    Anim { target: hc; property: "enter"; to: 1; curve: "spatial" }
                }
                Connections {
                    target: root
                    function onOpenChanged() {
                        if (root.open) {
                            hc.enter = 0;
                            enterAnim.restart();
                        }
                    }
                }

                onDismissed: Notifs.removeHistory(index)
                onActivated: Notifs.removeHistory(index)
            }

            // leer
            Column {
                anchors.centerIn: parent
                visible: list.count === 0
                spacing: 12
                opacity: visible ? 1 : 0

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84
                    height: 84
                    radius: 42
                    color: Theme.alpha(Theme.primary, 0.1)
                    Icon {
                        anchors.centerIn: parent
                        icon: Notifs.dnd ? "notifications_paused" : "notifications_off"
                        size: 40
                        color: Theme.primary
                    }
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Backend.tr("Keine Benachrichtigungen")
                    font.pixelSize: Theme.size.label
                    font.weight: Font.DemiBold
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Backend.tr("Neue Meldungen erscheinen hier.")
                    color: Theme.surfaceFgDim
                    font.pixelSize: Theme.size.small
                }
            }
        }
    }
}
