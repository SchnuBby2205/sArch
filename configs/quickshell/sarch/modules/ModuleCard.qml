import QtQuick
import qs.components
import qs.services

// Ein Bar-Modul in den Einstellungen: Zone, Reihenfolge, modul-spezifische Optionen
Card {
    id: root

    property var info
    property var page
    property bool expanded: false

    readonly property var mod: page.draft.modules.find(m => m.id === info.id) ?? { id: info.id, zone: "off" }
    readonly property var origMod: page.original.modules.find(m => m.id === info.id) ?? { id: info.id, zone: "off" }
    readonly property int idx: page.draft.modules.findIndex(m => m.id === info.id)
    readonly property bool off: mod.zone === "off"
    readonly property bool hasOptions: ["clock", "date", "workspaces", "audio"].indexOf(info.id) >= 0
    readonly property string optKey: info.id === "clock" ? "clock" : info.id === "date" ? "date" : info.id === "workspaces" ? "workspaces" : info.id === "audio" ? "audio" : ""
    readonly property bool modified: mod.zone !== origMod.zone || idx !== page.original.modules.findIndex(m => m.id === info.id)
                                     || (optKey !== "" && JSON.stringify(page.draft[optKey]) !== JSON.stringify(page.original[optKey]))

    readonly property var zoneLabels: page.vertical
        ? [Backend.t("qs_bar_off", "Aus"), Backend.t("qs_bar_top", "Oben"), Backend.t("qs_bar_center", "Mitte"), Backend.t("qs_bar_bottom", "Unten")]
        : [Backend.t("qs_bar_off", "Aus"), Backend.t("qs_bar_left", "Links"), Backend.t("qs_bar_center", "Mitte"), Backend.t("qs_bar_right", "Rechts")]

    height: 80 + (expanded ? body.implicitHeight + 18 : 0)
    clip: true
    highlighted: modified
    Behavior on height { Anim { curve: root.expanded ? "spatial" : "emphasized" } }

    // ── Kopf ──
    Item {
        width: parent.width
        height: 80

        Rectangle {
            id: bubble

            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            height: 46
            radius: root.off ? 15 : 23
            color: root.off ? Theme.surfaceHighest : Theme.primaryContainer
            Behavior on radius { Anim { curve: "spatial" } }
            Behavior on color { CAnim {} }

            Icon {
                anchors.centerIn: parent
                icon: root.info.icon
                size: 24
                fill: root.off ? 0 : 1
                color: root.off ? Theme.surfaceFgDim : Theme.primaryContainerFg
            }
        }

        Column {
            x: 76
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 76 - tools.width - 20
            spacing: 3

            Row {
                spacing: 8
                Txt {
                    text: root.info.label
                    font.pixelSize: Theme.size.label
                    font.weight: Font.Medium
                    opacity: root.off ? 0.6 : 1
                }
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.tertiary
                    anchors.verticalCenter: parent.verticalCenter
                    scale: root.modified ? 1 : 0
                    Behavior on scale { Anim { curve: "spatialFast" } }
                }
            }
            Txt {
                width: parent.width
                text: root.info.desc
                font.pixelSize: Theme.size.small
                color: Theme.surfaceFgDim
            }
        }

        Row {
            id: tools

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                options: ["off", "start", "center", "end"]
                labels: root.zoneLabels
                value: root.mod.zone
                segWidth: 70
                onPicked: v => root.page.setZone(root.info.id, v)
            }
            Item { width: 6; height: 1 }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "keyboard_arrow_up"
                size: 34
                disabled: root.idx <= 0
                onClicked: root.page.move(root.info.id, -1)
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "keyboard_arrow_down"
                size: 34
                disabled: root.idx >= root.page.draft.modules.length - 1
                onClicked: root.page.move(root.info.id, 1)
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "tune"
                size: 34
                active: root.expanded
                visible: root.hasOptions
                rotation: root.expanded ? 90 : 0
                Behavior on rotation { Anim { curve: "spatial" } }
                onClicked: root.expanded = !root.expanded
            }
            Item {
                visible: !root.hasOptions
                width: 34
                height: 1
            }
        }
    }

    // ── Optionen ──
    Item {
        id: body

        y: 80
        x: 20
        width: parent.width - 40
        implicitHeight: loader.implicitHeight + 16
        opacity: root.expanded ? 1 : 0
        Behavior on opacity { Anim { curve: "effects"; duration: root.expanded ? 320 : 120 } }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.alpha(Theme.outline, 0.15)
        }

        Loader {
            id: loader

            y: 14
            width: parent.width
            active: root.hasOptions
            sourceComponent: root.info.id === "clock" ? clockOpts
                           : root.info.id === "date" ? dateOpts
                           : root.info.id === "workspaces" ? wsOpts
                           : audioOpts
        }
    }

    component Toggle: Row {
        id: tg

        property string label
        property bool checked
        property var labels: [Backend.t("qs_off", "Aus"), Backend.t("qs_on", "An")]
        signal toggled(bool v)

        spacing: 14
        Txt {
            width: 190
            anchors.verticalCenter: parent.verticalCenter
            text: tg.label
            color: Theme.surfaceFgDim
        }
        Segmented {
            options: ["false", "true"]
            labels: tg.labels
            value: String(tg.checked)
            segWidth: 90
            onPicked: v => tg.toggled(v === "true")
        }
    }

    Component {
        id: clockOpts

        Column {
            spacing: 10
            Toggle {
                label: Backend.t("qs_bar_seconds", "Sekunden anzeigen")
                checked: root.page.draft.clock.seconds
                onToggled: v => root.page.set("clock.seconds", v)
            }
            Toggle {
                label: Backend.t("qs_bar_blink", "Doppelpunkt blinkt")
                checked: root.page.draft.clock.blink ?? true
                onToggled: v => root.page.set("clock.blink", v)
            }
            Toggle {
                label: Backend.t("qs_bar_24h", "Zeitformat")
                labels: ["12 h", "24 h"]
                checked: root.page.draft.clock.h24
                onToggled: v => root.page.set("clock.h24", v)
            }
        }
    }

    Component {
        id: dateOpts

        Column {
            spacing: 10
            width: parent?.width ?? 400

            Row {
                spacing: 12
                Field {
                    id: fmtField

                    width: 260
                    label: Backend.t("qs_bar_date_format", "Format (Qt-Datumsformat)")
                    mono: true
                    text: root.page.draft.date.format
                    onEdited: root.page.set("date.format", text)
                    Connections {
                        target: root.page
                        function onDraftChanged() {
                            if (fmtField.text !== root.page.draft.date.format)
                                fmtField.text = root.page.draft.date.format;
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Txt {
                        text: Backend.t("qs_bar_example", "Beispiel")
                        font.pixelSize: Theme.size.tiny
                        color: Theme.surfaceFgDim
                    }
                    Txt {
                        text: Time.now.toLocaleDateString(Qt.locale("de_DE"), root.page.draft.date.format)
                        font.pixelSize: Theme.size.label
                        font.weight: Font.DemiBold
                        color: Theme.primary
                    }
                }
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: ["ddd, d. MMM", "dddd, d. MMMM", "dd.MM.yyyy", "d. MMM yyyy", "ddd dd.MM."]
                    Rectangle {
                        id: chip

                        required property string modelData
                        readonly property bool sel: root.page.draft.date.format === modelData
                        width: chipTxt.implicitWidth + 24
                        height: 32
                        radius: 16
                        color: sel ? Theme.secondaryContainer : "transparent"
                        border.width: sel ? 0 : 1
                        border.color: Theme.alpha(Theme.outline, 0.4)
                        Txt {
                            id: chipTxt
                            anchors.centerIn: parent
                            text: Time.now.toLocaleDateString(Qt.locale("de_DE"), chip.modelData)
                            font.pixelSize: Theme.size.small
                            color: chip.sel ? Theme.secondaryContainerFg : Theme.surfaceFg
                        }
                        StateLayer {
                            radius: 16
                            onClicked: root.page.set("date.format", chip.modelData)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: wsOpts

        Column {
            spacing: 10
            width: parent?.width ?? 400

            Toggle {
                label: Backend.t("qs_bar_ws_style", "Darstellung")
                labels: [Backend.t("qs_bar_dots", "Punkte"), Backend.t("qs_bar_numbers", "Zahlen")]
                checked: root.page.draft.workspaces.numbers
                onToggled: v => root.page.set("workspaces.numbers", v)
            }
            Row {
                spacing: 14
                Txt {
                    width: 190
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.t("qs_bar_ws_count", "Mindestanzahl")
                    color: Theme.surfaceFgDim
                }
                SSlider {
                    id: wsSlider

                    width: 260
                    anchors.verticalCenter: parent.verticalCenter
                    from: 1
                    to: 10
                    stepSize: 1
                    value: root.page.draft.workspaces.count
                    onMoved: v => root.page.set("workspaces.count", v)
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.page.draft.workspaces.count
                    mono: true
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }
        }
    }

    Component {
        id: audioOpts

        Toggle {
            label: Backend.t("qs_bar_percent", "Prozent anzeigen")
            checked: root.page.draft.audio.percent
            onToggled: v => root.page.set("audio.percent", v)
        }
    }
}
