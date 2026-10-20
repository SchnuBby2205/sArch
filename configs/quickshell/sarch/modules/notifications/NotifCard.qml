import QtQuick
import qs.components
import qs.services

// Eine Benachrichtigung als Karte (Popup und Zentrale).
//  - nach rechts wischen oder X = schließen, Klick = Standard-Aktion
//  - Popup: Ablaufbalken unten, pausiert solange die Maus darüber ist
Item {
    id: root

    property string app: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    property int urgency: 1                 // 0 niedrig, 1 normal, 2 kritisch
    property real progress: -1              // 0..100, -1 = keiner
    property var actions: []                // [{ identifier, text }]
    property real time: Date.now()
    property int timeout: 0                 // ms, 0 = kein Ablauf (Zentrale/kritisch)
    property bool compact: false            // Zentrale: etwas kleiner, Body kürzer

    signal dismissed
    signal expired
    signal activated
    signal actionInvoked(string id)

    readonly property bool critical: urgency === 2
    readonly property color accent: critical ? Theme.error : Theme.primary
    readonly property bool hovered: hover.hovered
    readonly property string imgSrc: Notifs.iconSource(image)
    readonly property string iconSrc: Notifs.iconSource(appIcon)
    readonly property string symbol: Notifs.symbolFor(app, summary, progress)
    readonly property var realActions: (actions || []).filter(a => a.identifier !== "default" && a.text)

    implicitWidth: 380
    implicitHeight: card.height

    // ── Ablauf ──
    property real remaining: 1
    NumberAnimation on remaining {
        id: life

        running: root.timeout > 0
        paused: running && (root.hovered || drag.active)
        from: 1
        to: 0
        duration: Math.max(1, root.timeout)
        onFinished: root.expired()
    }
    function restartTimer() {
        if (timeout > 0)
            life.restart();
    }

    HoverHandler {
        id: hover
    }

    Rectangle {
        id: card

        width: parent.width
        height: content.implicitHeight + 28
        radius: Theme.radius.large
        color: Theme.alpha(Theme.surfaceContainer, 0.96)
        border.width: 1
        border.color: root.critical ? Theme.alpha(Theme.error, 0.55) : Theme.alpha(Theme.outline, root.hovered ? 0.32 : 0.18)
        Behavior on border.color { CAnim {} }
        clip: true

        // Wischen nach rechts
        x: 0
        opacity: 1 - Math.max(0, x) / (width * 1.1)
        DragHandler {
            id: drag

            target: card
            xAxis.minimum: -20
            yAxis.enabled: false
            onActiveChanged: if (!active) {
                if (card.x > card.width * 0.32)
                    flyOut.start();
                else
                    back.start();
            }
        }
        Anim { id: back; target: card; property: "x"; to: 0; curve: "spatial" }
        SequentialAnimation {
            id: flyOut
            Anim { target: card; property: "x"; to: card.width + 40; curve: "emphasizedAccel"; duration: 220 }
            ScriptAction { script: root.dismissed() }
        }

        // weicher Akzent-Verlauf von links
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: root.critical ? 1 : 0.7
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.alpha(root.accent, 0.14) }
                GradientStop { position: 0.45; color: Theme.alpha(root.accent, 0.0) }
            }
        }

        // Klick auf die Karte
        TapHandler {
            onTapped: root.activated()
        }

        Row {
            id: content

            x: 14
            y: 14
            width: parent.width - 28
            spacing: 12

            // Icon / Bild
            Item {
                id: iconBox

                width: root.compact ? 40 : 46
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width * 0.32
                    color: root.critical ? Theme.errorContainer : Theme.primaryContainer
                    visible: bigImg.status !== Image.Ready && appImg.status !== Image.Ready

                    Icon {
                        anchors.centerIn: parent
                        icon: root.critical ? "warning" : root.symbol
                        size: parent.width * 0.52
                        fill: 1
                        color: root.critical ? Theme.errorContainerFg : Theme.primaryContainerFg
                    }
                }
                RoundedImage {
                    id: bigImg

                    anchors.fill: parent
                    radius: width * 0.32
                    source: root.imgSrc
                    visible: status === Image.Ready
                }
                Image {
                    id: appImg

                    anchors.fill: parent
                    anchors.margins: 3
                    source: root.imgSrc === "" ? root.iconSrc : ""
                    sourceSize.width: 96
                    sourceSize.height: 96
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }
                // kleines App-Icon auf dem großen Bild
                Image {
                    visible: bigImg.visible && root.iconSrc !== "" && status === Image.Ready
                    width: 18
                    height: 18
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -3
                    source: root.imgSrc !== "" ? root.iconSrc : ""
                    sourceSize.width: 36
                    sourceSize.height: 36
                }
            }

            Column {
                width: parent.width - iconBox.width - parent.spacing
                spacing: 3

                // Kopf: App · Zeit · X
                Item {
                    width: parent.width
                    height: 18

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - when.width - 34
                        text: root.app || "Benachrichtigung"
                        font.pixelSize: Theme.size.tiny
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.4
                        color: root.critical ? Theme.error : Theme.surfaceFgDim
                        elide: Text.ElideRight
                    }
                    Txt {
                        id: when

                        anchors.right: parent.right
                        anchors.rightMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        text: Notifs.ago(root.time, Time.now.getTime())
                        font.pixelSize: Theme.size.tiny
                        color: Theme.surfaceFgDim
                        opacity: root.hovered ? 0 : 0.8
                        Behavior on opacity { Anim { curve: "effects" } }
                    }
                    IconButton {
                        anchors.right: parent.right
                        anchors.rightMargin: -6
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "close"
                        size: 26
                        opacity: root.hovered ? 1 : 0
                        scale: root.hovered ? 1 : 0.6
                        Behavior on opacity { Anim { curve: "effects" } }
                        Behavior on scale { Anim { curve: "spatialFast" } }
                        onClicked: flyOut.start()
                    }
                }

                Txt {
                    width: parent.width
                    visible: text !== ""
                    text: root.summary
                    font.pixelSize: Theme.size.label
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    visible: text !== ""
                    text: root.body
                    textFormat: Text.StyledText
                    font.pixelSize: Theme.size.small + 1
                    color: Theme.surfaceFgDim
                    wrapMode: Text.Wrap
                    maximumLineCount: root.compact ? 3 : 5
                    elide: Text.ElideRight
                    linkColor: Theme.primary
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }

                // Fortschritt (z. B. Lautstärke)
                Item {
                    visible: root.progress >= 0
                    width: parent.width
                    height: 16

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - pct.width - 10
                        height: 6
                        radius: 3
                        color: Theme.alpha(root.accent, 0.18)

                        Rectangle {
                            width: parent.width * root.progress / 100
                            height: parent.height
                            radius: 3
                            color: root.accent
                            Behavior on width { Anim { curve: "spatialFast" } }
                        }
                    }
                    Txt {
                        id: pct

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${Math.round(root.progress)}%`
                        font.pixelSize: Theme.size.tiny
                        font.weight: Font.DemiBold
                        color: Theme.surfaceFgDim
                    }
                }

                // Aktionen
                Flow {
                    visible: root.realActions.length > 0
                    width: parent.width
                    spacing: 6
                    topPadding: 6

                    Repeater {
                        model: root.realActions

                        Rectangle {
                            id: chip

                            required property var modelData
                            width: chipTxt.implicitWidth + 24
                            height: 30
                            radius: 15
                            color: Theme.alpha(root.accent, chipArea.containsMouse ? 0.26 : 0.14)
                            Behavior on color { CAnim {} }

                            Txt {
                                id: chipTxt

                                anchors.centerIn: parent
                                text: chip.modelData.text
                                font.pixelSize: Theme.size.small
                                font.weight: Font.DemiBold
                                color: root.accent
                            }
                            StateLayer {
                                id: chipArea

                                radius: 15
                                tint: root.accent
                                onClicked: root.actionInvoked(chip.modelData.identifier)
                            }
                        }
                    }
                }
            }
        }

        // Ablaufbalken
        Rectangle {
            visible: root.timeout > 0
            anchors.bottom: parent.bottom
            x: 16
            width: (parent.width - 32) * root.remaining
            height: 2
            radius: 1
            color: root.accent
            opacity: root.hovered ? 0.25 : 0.55
        }
    }
}
