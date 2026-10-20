import QtQuick
import QtQuick.Effects
import qs.components
import qs.services

// Die komplette Einstellungs-Oberfläche: Scrim, Glas-Panel mit geblurrtem Wallpaper,
// Sidebar, Inhalt, Toasts und Dialoge. Öffnen/Schließen ist voll animiert.
Item {
    id: root

    property bool open: false
    property string startPage: ""

    signal closed      // nach der Schließ-Animation

    function show(page) {
        startPage = page || "";
        Backend.reload(() => {
            const target = Backend.resolvePage(startPage) || Ui.current || (Backend.categories[0]?.name ?? "");
            if (Ui.current === "" || Ui.current !== target) {
                Ui.current = "";
                Ui.navigate(target, true);
            } else {
                Ui.navigated(target);   // Seite neu aufbauen (frische Werte)
            }
        });
        Theme.reloadColors();
        open = true;
        forceActiveFocus();
    }

    function requestClose(force) {
        if (dialogs.isOpen) {
            dialogs.close();
            return;
        }
        if (!force && Ui.pendingCount > 0) {
            Ui.confirm({
                title: Backend.t("qs_discard_heading", "Änderungen verwerfen?"),
                body: Backend.t("qs_discard_body", "Auf dieser Seite gibt es {n} nicht übernommene Änderungen.", { n: Ui.pendingCount }),
                ok: Backend.t("qs_discard", "Verwerfen"),
                danger: true,
                icon: "edit_off"
            }, () => root.requestClose(true));
            return;
        }
        Ui.search = "";
        open = false;
    }

    function cycle(d) {
        const names = sidebar.filtered.map(f => f.cat.name);
        if (!names.length)
            return;
        const i = names.indexOf(Ui.current);
        Ui.navigate(names[(i + d + names.length) % names.length]);
    }

    focus: true
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape) {
            if (!dialogs.isOpen && Ui.search !== "") {
                Ui.search = "";
                root.forceActiveFocus();
            } else {
                root.requestClose(false);
            }
            e.accepted = true;
        } else if (e.modifiers & Qt.ControlModifier) {
            if (e.key === Qt.Key_S) {
                Ui.requestApply();
                e.accepted = true;
            } else if (e.key === Qt.Key_F) {
                sidebar.searchField.forceFocus();
                e.accepted = true;
            } else if (e.key === Qt.Key_Z) {
                Ui.requestReset();
                e.accepted = true;
            } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_PageDown || e.key === Qt.Key_Down) {
                root.cycle(1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_PageUp || e.key === Qt.Key_Up) {
                root.cycle(-1);
                e.accepted = true;
            } else if (e.key === Qt.Key_W || e.key === Qt.Key_Q) {
                root.requestClose(false);
                e.accepted = true;
            }
        }
    }

    Component.onCompleted: Ui.dialogHost = dialogs

    // ── Scrim ──
    Rectangle {
        id: scrim

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: root.open ? 1 : 0
        Behavior on opacity { Anim { curve: "standard"; duration: root.open ? 450 : 300 } }

        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.requestClose(false)
        }
    }

    // ── Panel ──
    Item {
        id: panel

        readonly property real w: Math.min(1320, root.width - 80)
        readonly property real h: Math.min(860, root.height - 80)

        width: w
        height: h
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.open ? 0 : 70

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.9

        Behavior on anchors.verticalCenterOffset { Anim { curve: root.open ? "spatialSlow" : "emphasizedAccel"; duration: root.open ? 700 : 260 } }
        Behavior on scale { Anim { curve: root.open ? "spatialSlow" : "emphasizedAccel"; duration: root.open ? 700 : 260 } }
        Behavior on opacity {
            SequentialAnimation {
                Anim { curve: root.open ? "effects" : "emphasizedAccel"; duration: root.open ? 300 : 260 }
                ScriptAction { script: if (!root.open) root.closed() }
            }
        }

        MouseArea {
            anchors.fill: parent
        } // Klicks nicht zum Scrim

        // Schatten
        Rectangle {
            id: shadowSrc

            anchors.fill: parent
            radius: Theme.radius.xl
            color: "black"
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: shadowSrc
            source: shadowSrc
            shadowEnabled: true
            shadowColor: "black"
            shadowBlur: 1.0
            shadowOpacity: 0.6
            shadowVerticalOffset: 18
            autoPaddingEnabled: true
        }

        // geblurrtes Wallpaper als Glas-Hintergrund (crossfade bei Vorschau/Wechsel)
        Item {
            id: bg

            anchors.fill: parent
            readonly property string src: Theme.previewWallpaper !== "" ? Theme.previewWallpaper : Theme.wallpaper
            property bool aFront: true

            onSrcChanged: {
                const url = src ? "file://" + src : "";
                const back = aFront ? bgB : bgA;
                if (String((aFront ? bgA : bgB).source) === url)
                    return;
                back.source = url;
                if (back.status === Image.Ready)
                    aFront = back === bgA;          // eindeutig (Cache-Treffer meldet Ready schon beim Setzen)
            }

            Item {
                id: bgImages

                anchors.fill: parent
                visible: false

                Image {
                    id: bgA

                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 960
                    asynchronous: true
                    opacity: bg.aFront ? 1 : 0
                    Behavior on opacity { Anim { curve: "standard"; duration: 900 } }
                    onStatusChanged: if (status === Image.Ready && !bg.aFront && String(source) === "file://" + bg.src)
                        bg.aFront = true
                }
                Image {
                    id: bgB

                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 960
                    asynchronous: true
                    opacity: bg.aFront ? 0 : 1
                    Behavior on opacity { Anim { curve: "standard"; duration: 900 } }
                    onStatusChanged: if (status === Image.Ready && bg.aFront && String(source) === "file://" + bg.src)
                        bg.aFront = false
                }
            }

            MultiEffect {
                anchors.fill: parent
                source: bgImages
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                blurMultiplier: 1.4
                saturation: 0.25
                brightness: -0.08
                maskEnabled: true
                maskSource: panelMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Rectangle {
                id: panelMask

                anchors.fill: parent
                radius: Theme.radius.xl
                visible: false
                layer.enabled: true
            }
        }

        // Tönung (Glas)
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.xl
            color: Theme.alpha(Theme.surface, 0.80)
            border.width: 1
            border.color: Theme.alpha(Theme.outline, 0.22)
        }

        // Sidebar-Fläche
        Rectangle {
            id: sideBg

            x: 10
            y: 10
            width: 290
            height: parent.height - 20
            radius: Theme.radius.xl - 8
            color: Theme.alpha(Theme.surfaceLow, 0.72)
        }

        Sidebar {
            id: sidebar

            x: sideBg.x
            y: sideBg.y
            width: sideBg.width
            height: sideBg.height

            // gestaffeltes Einfliegen beim Öffnen
            opacity: root.open ? 1 : 0
            transform: Translate {
                x: root.open ? 0 : -30
                Behavior on x { Anim { curve: "spatialSlow"; duration: 800 } }
            }
            Behavior on opacity { SequentialAnimation { PauseAnimation { duration: root.open ? 120 : 0 } Anim { curve: "effects"; duration: 350 } } }
        }

        ContentHost {
            id: content

            x: sideBg.x + sideBg.width + 28
            y: 18
            width: parent.width - x - 20
            height: parent.height - y - 10

            opacity: root.open ? 1 : 0
            transform: Translate {
                y: root.open ? 0 : 30
                Behavior on y { Anim { curve: "spatialSlow"; duration: 850 } }
            }
            Behavior on opacity { SequentialAnimation { PauseAnimation { duration: root.open ? 200 : 0 } Anim { curve: "effects"; duration: 350 } } }
        }

        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 22
            icon: "close"
            size: 44
            tooltip: Backend.t("qs_close", "Schließen (Esc)")
            onClicked: root.requestClose(false)
        }

        // Ladefehler Backend
        Rectangle {
            anchors.centerIn: content
            width: Math.min(520, content.width - 40)
            height: errCol.implicitHeight + 40
            radius: Theme.radius.large
            color: Theme.errorContainer
            visible: Backend.lastError !== "" && !Backend.loaded

            Column {
                id: errCol

                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 8

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: "report"
                    size: 40
                    fill: 1
                    color: Theme.errorContainerFg
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideNone
                    horizontalAlignment: Text.AlignHCenter
                    text: Backend.lastError + "\n\n" + Backend.backend
                    mono: true
                    font.pixelSize: Theme.size.small
                    color: Theme.errorContainerFg
                }
            }
        }

        ToastHost {
            anchors.horizontalCenter: content.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 96
            z: 800
        }

        DialogHost {
            id: dialogs

            anchors.fill: parent
        }
    }
}
