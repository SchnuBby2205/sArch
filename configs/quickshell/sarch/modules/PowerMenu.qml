import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.components
import qs.services
import qs.modules.bar

// Powermenü: Vollbild-Glas mit großer Uhr, sechs Aktionen, Countdown-Ring für
// Abmelden / Neustart / Herunterfahren (nochmal drücken = sofort, Esc = abbrechen)
Item {
    id: root

    property bool open: false
    property int selected: 0
    property string armed: ""
    property real armProgress: 0
    property string uptimeText: ""

    signal closed

    readonly property string script: `${Quickshell.env("HOME")}/.config/sArch/bin/sarch_power_action.sh`
    readonly property string user: Quickshell.env("USER") || ""

    readonly property var actions: [
        { id: "lock", icon: "lock", label: Backend.t("qs_pw_lock", "Sperren"), key: "L", confirm: false, accent: "primary" },
        { id: "suspend", icon: "bedtime", label: Backend.t("qs_pw_suspend", "Bereitschaft"), key: "S", confirm: false, accent: "primary" },
        { id: "hibernate", icon: "mode_standby", label: Backend.t("qs_pw_hibernate", "Ruhezustand"), key: "H", confirm: false, accent: "primary" },
        { id: "logout", icon: "logout", label: Backend.t("qs_pw_logout", "Abmelden"), key: "E", confirm: true, accent: "tertiary" },
        { id: "reboot", icon: "restart_alt", label: Backend.t("qs_pw_reboot", "Neustart"), key: "R", confirm: true, accent: "tertiary" },
        { id: "shutdown", icon: "power_settings_new", label: Backend.t("qs_pw_shutdown", "Herunterfahren"), key: "P", confirm: true, accent: "error" }
    ]

    function show() {
        armed = "";
        armProgress = 0;
        selected = 0;
        uptimeProc.running = true;
        open = true;
        forceActiveFocus();
    }
    function requestClose() {
        if (armed !== "") {
            cancelArm();
            return;
        }
        open = false;
    }
    function cancelArm() {
        armAnim.stop();
        armed = "";
        armProgress = 0;
    }

    property string pending: ""
    function trigger(i) {
        const a = actions[i];
        if (!a)
            return;
        selected = i;
        if (a.confirm && armed !== a.id) {
            armed = a.id;
            armAnim.restart();
            return;
        }
        run(a.id);
    }
    function run(id) {
        armAnim.stop();
        pending = id;
        open = false;          // erst ausblenden, dann ausführen (Sperrbildschirm nicht verdecken)
    }

    NumberAnimation {
        id: armAnim

        target: root
        property: "armProgress"
        from: 0
        to: 1
        duration: 2200
        onFinished: if (root.armed !== "")
            root.run(root.armed)
    }

    Process {
        id: uptimeProc

        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            id: upOut
        }
        onExited: Qt.callLater(() => {
            const sec = Math.floor(parseFloat(upOut.text) || 0);
            const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
            root.uptimeText = (d ? `${d} d ` : "") + (h ? `${h} h ` : "") + `${m} min`;
        })
    }

    focus: true
    Keys.onPressed: e => {
        const k = e.key;
        if (k === Qt.Key_Escape) {
            requestClose();
        } else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab) {
            cancelArm();
            selected = (selected - 1 + actions.length) % actions.length;
        } else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab) {
            cancelArm();
            selected = (selected + 1) % actions.length;
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            trigger(selected);
        } else {
            const t = e.text.toUpperCase();
            const i = actions.findIndex(a => a.key === t);
            if (i >= 0)
                trigger(i);
            else
                return;
        }
        e.accepted = true;
    }

    // ── Hintergrund: ganzer Bildschirm geblurrt ──
    Item {
        id: bg

        anchors.fill: parent
        opacity: root.open ? 1 : 0
        Behavior on opacity {
            SequentialAnimation {
                Anim { curve: root.open ? "standard" : "emphasizedAccel"; duration: root.open ? 420 : 280 }
                ScriptAction {
                    script: if (!root.open) {
                        root.closed();
                        if (root.pending !== "") {
                            Quickshell.execDetached([root.script, root.pending]);
                            root.pending = "";
                        }
                        root.armed = "";
                        root.armProgress = 0;
                    }
                }
            }
        }

        Image {
            id: wp

            anchors.fill: parent
            visible: false
            source: Theme.wallpaper !== "" ? "file://" + Theme.wallpaper : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 1280
            asynchronous: true
        }
        MultiEffect {
            anchors.fill: parent
            source: wp
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            blurMultiplier: 1.6
            saturation: 0.2
            scale: root.open ? 1 : 1.08
            Behavior on scale { Anim { curve: "emphasizedDecel"; duration: 900 } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.alpha(Theme.surface, 0.62) }
                GradientStop { position: 1; color: Theme.alpha(Theme.surfaceLowest, 0.86) }
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.requestClose()
        }
    }

    // ── Uhr & Gruß ──
    Column {
        id: head

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: buttons.top
        anchors.bottomMargin: 56
        spacing: 6
        opacity: root.open ? 1 : 0
        property real dy: root.open ? 0 : -40
        transform: Translate { y: head.dy }
        Behavior on opacity { Anim { curve: "effects"; duration: 400 } }
        Behavior on dy { Anim { curve: "spatialSlow"; duration: 800 } }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property string hh: String(Time.now.getHours()).padStart(2, "0")
            readonly property string mm: String(Time.now.getMinutes()).padStart(2, "0")

            RollingDigit { digit: parent.hh[0]; pixelSize: 112; weight: Font.Bold }
            RollingDigit { digit: parent.hh[1]; pixelSize: 112; weight: Font.Bold }
            Txt {
                text: ":"
                mono: true
                font.pixelSize: 112
                font.weight: Font.Bold
                color: Theme.primary
            }
            RollingDigit { digit: parent.mm[0]; pixelSize: 112; weight: Font.Bold }
            RollingDigit { digit: parent.mm[1]; pixelSize: 112; weight: Font.Bold }
        }
        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Time.now.toLocaleDateString(Qt.locale("de_DE"), "dddd, d. MMMM yyyy")
            font.pixelSize: Theme.size.title + 2
            color: Theme.surfaceFgDim
        }
        Item { width: 1; height: 10 }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: chipRow.implicitWidth + 28
            height: 36
            radius: 18
            color: Theme.alpha(Theme.surfaceHigh, 0.7)
            border.width: 1
            border.color: Theme.alpha(Theme.outline, 0.2)

            Row {
                id: chipRow

                anchors.centerIn: parent
                spacing: 10

                Icon {
                    icon: "waving_hand"
                    size: 18
                    fill: 1
                    color: Theme.tertiary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    text: root.user !== "" ? Backend.t("qs_pw_greeting", "Bis bald, {user}", { user: root.user }) : Backend.t("qs_pw_greeting_anon", "Bis bald!")
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    visible: root.uptimeText !== ""
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.surfaceFgDim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    visible: root.uptimeText !== ""
                    text: Backend.t("qs_pw_uptime", "läuft seit {t}", { t: root.uptimeText })
                    color: Theme.surfaceFgDim
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Aktionen ──
    Row {
        id: buttons

        anchors.centerIn: parent
        anchors.verticalCenterOffset: 70
        spacing: 22

        Repeater {
            model: root.actions

            Item {
                id: btn

                required property var modelData
                required property int index

                readonly property bool sel: root.selected === index
                readonly property bool isArmed: root.armed === modelData.id
                readonly property color accent: modelData.accent === "error" ? Theme.error
                                              : modelData.accent === "tertiary" ? Theme.tertiary : Theme.primary
                readonly property color accentFg: modelData.accent === "error" ? Theme.errorFg
                                                : modelData.accent === "tertiary" ? Theme.surfaceLowest : Theme.primaryFg
                readonly property bool lit: sel || area.containsMouse || isArmed

                width: 132
                height: 188

                // Einfliegen beim Öffnen (gestaffelt)
                opacity: root.open ? 1 : 0
                property real dy: root.open ? 0 : 80
                transform: Translate { y: btn.dy }
                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: root.open ? 80 + btn.index * 55 : 0 }
                        Anim { curve: "effects"; duration: 300 }
                    }
                }
                Behavior on dy {
                    SequentialAnimation {
                        PauseAnimation { duration: root.open ? 80 + btn.index * 55 : 0 }
                        Anim { curve: root.open ? "spatialSlow" : "emphasizedAccel"; duration: root.open ? 700 : 220 }
                    }
                }

                Rectangle {
                    id: tile

                    width: 132
                    height: 132
                    radius: btn.lit ? 66 : 34
                    color: btn.lit ? btn.accent : Theme.alpha(Theme.surfaceHigh, 0.72)
                    border.width: btn.lit ? 0 : 1
                    border.color: Theme.alpha(Theme.outline, 0.25)
                    scale: area.pressed ? 0.92 : btn.lit ? 1.06 : 1
                    Behavior on radius { Anim { curve: "spatial" } }
                    Behavior on color { CAnim { duration: 260 } }
                    Behavior on scale { Anim { curve: "spatialFast" } }

                    Icon {
                        anchors.centerIn: parent
                        icon: btn.modelData.icon
                        size: 54
                        fill: btn.lit ? 1 : 0
                        weight: btn.lit ? 600 : 400
                        color: btn.lit ? btn.accentFg : Theme.surfaceFg
                        rotation: btn.lit && btn.modelData.id === "reboot" ? 360 : 0
                        Behavior on rotation { Anim { curve: "spatialSlow"; duration: 900 } }
                    }

                    // Countdown-Ring
                    Shape {
                        anchors.fill: parent
                        anchors.margins: -10
                        visible: btn.isArmed
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: btn.accent
                            strokeWidth: 5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: 76
                                centerY: 76
                                radiusX: 73
                                radiusY: 73
                                startAngle: -90
                                sweepAngle: 360 * root.armProgress
                            }
                        }
                    }

                    StateLayer {
                        id: area

                        radius: tile.radius
                        tint: btn.accentFg
                        hoverOpacity: 0
                        onEntered: {
                            if (root.armed !== "" && root.armed !== btn.modelData.id)
                                root.cancelArm();
                            root.selected = btn.index;
                        }
                        onClicked: root.trigger(btn.index)
                    }
                }

                Txt {
                    anchors.horizontalCenter: tile.horizontalCenter
                    y: 148
                    text: btn.isArmed ? Backend.t("qs_pw_again", "Nochmal = sofort") : btn.modelData.label
                    font.pixelSize: Theme.size.label
                    font.weight: btn.lit ? Font.DemiBold : Font.Normal
                    color: btn.lit ? Theme.surfaceFg : Theme.surfaceFgDim
                }
                Keycap {
                    anchors.horizontalCenter: tile.horizontalCenter
                    y: 172
                    label: btn.modelData.key
                    accent: btn.lit
                    opacity: btn.lit ? 1 : 0.5
                    scale: 0.8
                }
            }
        }
    }

    // ── Hinweis unten ──
    Txt {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        opacity: root.open ? 0.8 : 0
        Behavior on opacity { Anim { curve: "effects"; duration: 500 } }
        text: root.armed !== ""
            ? Backend.t("qs_pw_armed", "{a} in {s} s – nochmal drücken für sofort, Esc bricht ab", {
                a: root.actions.find(a => a.id === root.armed)?.label ?? "",
                s: Math.max(0, (2.2 * (1 - root.armProgress))).toFixed(1)
            })
            : Backend.t("qs_pw_hint", "← → wählen  ·  Enter ausführen  ·  Buchstabe = direkt  ·  Esc schließen")
        color: root.armed !== "" ? Theme.tertiary : Theme.surfaceFgDim
        font.pixelSize: Theme.size.body
    }
}
