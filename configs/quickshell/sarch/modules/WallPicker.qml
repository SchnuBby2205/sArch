import QtQuick
import Quickshell
import qs.components
import qs.services

// Schneller Wallpaper-Picker (SUPER+W): Filmstreifen unten am Bildschirm.
// Auswahl schließt den Picker sofort – der Übergang (awww / Zerschneiden / Kacheln) ist dann frei sichtbar.
//   ← →  wählen · Enter übernehmen · 1–5 mit Akzentfarbe · Tippen filtert · Esc schließt
Item {
    id: root

    property bool open: false
    property string query: ""
    property var items: []
    property int activeIndex: 0                 // Farbindex des aktiven Wallpapers
    property var colorCache: ({})
    property bool thumbing: false
    property bool warming: false
    property bool loading: false

    signal closed

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        return q === "" ? items : items.filter(w => w.name.toLowerCase().includes(q));
    }
    readonly property var cur: shown[strip.currentIndex] ?? null
    readonly property var curColors: cur ? (colorCache[cur.path] ?? []) : []
    readonly property var curType: WallTrans.types.find(t => t.id === WallTrans.type) ?? null

    function show() {
        query = "";
        search.text = "";
        open = true;
        load();
        Qt.callLater(() => search.forceFocus());
    }
    function requestClose() {
        open = false;
    }

    function load() {
        loading = items.length === 0;
        Backend.call(["wallpapers"], res => {
            loading = false;
            if (!res.ok)
                return;
            items = res.items;
            activeIndex = res.index || 0;
            // Farben aus dem Backend-Cache sofort übernehmen, fehlende im Hintergrund berechnen
            const cc = Object.assign({}, colorCache);
            for (const w of res.items)
                if (w.colors)
                    cc[w.path] = w.colors;
            colorCache = cc;
            if (res.missingColors > 0 && !warming) {
                warming = true;
                Backend.call(["colors-all"], r => {
                    warming = false;
                    if (!r.ok)
                        return;
                    const c2 = Object.assign({}, colorCache);
                    for (const p in r.colors)
                        if ((r.colors[p] || []).length || c2[p] === undefined)
                            c2[p] = r.colors[p];
                    colorCache = c2;
                });
            }
            if (res.current)
                Theme.wallpaper = res.current;
            Qt.callLater(() => focusPath(res.current || Theme.wallpaper));
            if (res.missing > 0 && !thumbing) {
                thumbing = true;
                Backend.call(["thumbs"], () => {
                    thumbing = false;
                    load();
                });
            }
        });
    }
    function focusPath(path) {
        const i = Math.max(0, shown.findIndex(w => w.path === path));
        strip.currentIndex = i;
        strip.positionViewAtIndex(i, ListView.Center);
    }
    function fetchColors(path) {
        if (!path || colorCache[path] !== undefined)
            return;
        Backend.call(["colors", path], res => {
            const c = Object.assign({}, colorCache);
            c[res.path || path] = res.colors || [];
            colorCache = c;
        });
    }
    onCurChanged: if (cur) {
        fetchColors(cur.path);
        WallFxState.prefetch = cur.path;     // für Kacheln/Zerschneiden vorab dekodieren
    }

    function move(d) {
        if (shown.length === 0)
            return;
        strip.currentIndex = (strip.currentIndex + d + shown.length) % shown.length;
    }
    function randomPick() {
        if (shown.length < 2)
            return;
        let i;
        do
            i = Math.floor(Math.random() * shown.length);
        while (shown[i].path === Theme.wallpaper);
        strip.currentIndex = i;
        pick(i, 0, "");
    }

    // übernehmen: Picker schnell ausblenden, direkt danach startet der Übergang
    function pick(i, idx, hex) {
        const w = shown[i];
        if (!w)
            return;
        requestClose();
        if (w.path === WallTrans.current() && idx === activeIndex)
            return;
        const cols = colorCache[w.path] ?? [];
        // erst setzen, wenn der Picker weg ist: der Übergang (v. a. Zerschneiden/Kacheln) lädt das
        // Bild in voller Größe – parallel zur Ausblend-Animation ließ das den Picker kurz hängen
        pending = { path: w.path, idx: idx, hex: hex || cols[idx] || "" };
    }
    property var pending: null
    onClosed: if (pending) {
        const p = pending;
        pending = null;
        WallTrans.applyWallpaper(p.path, p.idx, p.hex, res => {
            if (res.superseded)
                return;
            if (res.ok) {
                root.activeIndex = p.idx;
            } else {
                console.warn("sarch wallpaper:", res.error);
                Quickshell.execDetached(["notify-send", "-a", "sArch", "-u", "critical",
                    Backend.tr("Hintergrundbild konnte nicht gesetzt werden"), String(res.error || "?")]);
            }
        });
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.32)
        opacity: root.open ? 1 : 0
        Behavior on opacity { Anim { curve: "standard"; duration: root.open ? 380 : 160 } }

        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.requestClose()
            onWheel: w => root.move(w.angleDelta.y > 0 ? -1 : 1)
        }
    }

    // ── Panel ──
    Item {
        id: panel

        width: Math.min(root.width - 48, 1480)
        height: 356
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - height - 36 + (root.open ? 0 : 90)
        opacity: root.open ? 1 : 0

        Behavior on y { Anim { curve: root.open ? "spatialSlow" : "emphasizedAccel"; duration: root.open ? 620 : 160 } }
        Behavior on opacity {
            SequentialAnimation {
                Anim { curve: root.open ? "effects" : "emphasizedAccel"; duration: root.open ? 260 : 160 }
                ScriptAction { script: if (!root.open) root.closed() }
            }
        }

        MouseArea {
            anchors.fill: parent
            onWheel: w => root.move(w.angleDelta.y > 0 || w.angleDelta.x > 0 ? -1 : 1)
        }

        GlassPanel {
            anchors.fill: parent
            radius: Theme.radius.xl
            tint: 0.82
        }

        // Kopfzeile
        Item {
            id: head

            x: 22
            y: 18
            width: parent.width - 44
            height: 44

            Rectangle {
                id: bubble

                width: 44
                height: 44
                radius: 15
                color: Theme.tertiaryContainer
                Icon {
                    anchors.centerIn: parent
                    icon: "wallpaper"
                    size: 24
                    fill: 1
                    color: Theme.tertiaryContainerFg
                }
            }
            Column {
                anchors.left: bubble.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Txt {
                    text: Backend.tr("Hintergrundbild")
                    font.pixelSize: Theme.size.title
                    font.weight: Font.DemiBold
                }
                Txt {
                    text: Backend.tr("Übergang: {name}", { name: root.curType?.label ?? WallTrans.type })
                    font.pixelSize: Theme.size.small
                    color: Theme.surfaceFgDim
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Field {
                    id: search

                    width: 280
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    icon: "search"
                    placeholder: Backend.tr("Bilder filtern …")
                    onEdited: {
                        root.query = text;
                        Qt.callLater(() => root.focusPath(root.cur?.path ?? Theme.wallpaper));
                    }
                    onAccepted: root.pick(strip.currentIndex, 0, "")
                    keyHandler: e => {
                        if (e.key === Qt.Key_Escape)
                            root.requestClose();
                        else if (e.key === Qt.Key_Left && search.input.cursorPosition === 0)
                            root.move(-1);
                        else if (e.key === Qt.Key_Right && search.input.cursorPosition === search.text.length)
                            root.move(1);
                        else if (e.key === Qt.Key_Tab)
                            root.move(1);
                        else if (e.key === Qt.Key_Backtab)
                            root.move(-1);
                        else if (search.text === "" && e.key >= Qt.Key_1 && e.key <= Qt.Key_5) {
                            const n = e.key - Qt.Key_1;
                            if (n < root.curColors.length)
                                root.pick(strip.currentIndex, n, root.curColors[n]);
                        } else {
                            e.accepted = false;
                            return;
                        }
                        e.accepted = true;
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: countTxt.implicitWidth + 20
                    height: 30
                    radius: 15
                    color: Theme.alpha(Theme.primary, 0.14)
                    Txt {
                        id: countTxt

                        anchors.centerIn: parent
                        text: root.shown.length > 0 ? `${strip.currentIndex + 1} / ${root.shown.length}` : "0"
                        font.pixelSize: Theme.size.small
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Theme.primary
                    }
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "shuffle"
                    tooltip: Backend.tr("Zufälliges Bild")
                    onClicked: root.randomPick()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "tune"
                    tooltip: Backend.tr("Alle Einstellungen")
                    onClicked: {
                        root.requestClose();
                        Ui.openRequested("wallpaper");
                    }
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    onClicked: root.requestClose()
                }
            }
        }

        // Filmstreifen
        ListView {
            id: strip

            readonly property real cardW: 252
            readonly property real cardH: 150

            x: 0
            y: head.y + head.height + 14
            width: parent.width
            height: 214
            orientation: ListView.Horizontal
            spacing: 14
            clip: true
            model: root.shown
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (width - cardW) / 2
            preferredHighlightEnd: (width + cardW) / 2
            highlightMoveDuration: 320
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 1200

            delegate: Item {
                id: card

                required property var modelData
                required property int index
                readonly property bool sel: ListView.isCurrentItem
                readonly property bool active: modelData.path === Theme.wallpaper

                width: strip.cardW
                height: strip.height

                // gestaffelt einfliegen
                property real enter: root.open ? 1 : 0
                Behavior on enter {
                    SequentialAnimation {
                        PauseAnimation { duration: root.open ? Math.min(8, Math.abs(card.index - strip.currentIndex)) * 35 : 0 }
                        Anim { curve: "spatial" }
                    }
                }
                opacity: enter
                transform: Translate { y: (1 - card.enter) * 40 }

                Item {
                    id: frame

                    width: strip.cardW
                    height: strip.cardH
                    y: 18
                    scale: card.sel ? 1.12 : hov.hovered ? 1.03 : 0.94
                    opacity: card.sel ? 1 : 0.72
                    Behavior on scale { Anim { curve: "spatialFast" } }
                    Behavior on opacity { Anim { curve: "effects" } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: Theme.radius.large + 4
                        color: "transparent"
                        border.width: card.sel ? 3 : 0
                        border.color: Theme.primary
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius.large
                        color: Theme.surfaceHigh
                    }
                    RoundedImage {
                        anchors.fill: parent
                        radius: Theme.radius.large
                        source: card.modelData.thumb ? "file://" + card.modelData.thumb : "file://" + card.modelData.path
                        sourceSize.width: 504
                        sourceSize.height: 300
                    }
                    // aktiv
                    Rectangle {
                        visible: card.active
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        width: 26
                        height: 26
                        radius: 13
                        color: Theme.primary
                        Icon {
                            anchors.centerIn: parent
                            icon: "check"
                            size: 18
                            color: Theme.primaryFg
                        }
                    }
                    HoverHandler {
                        id: hov
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (card.sel)
                                root.pick(card.index, 0, "");
                            else
                                strip.currentIndex = card.index;
                        }
                        onDoubleClicked: root.pick(card.index, 0, "")
                    }
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: frame.y + frame.height + 18
                    width: parent.width - 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: card.modelData.name
                    font.pixelSize: Theme.size.small + 1
                    font.weight: card.sel ? Font.DemiBold : Font.Normal
                    color: card.sel ? Theme.surfaceFg : Theme.surfaceFgDim
                }
            }

            // leer / lädt
            Txt {
                anchors.centerIn: parent
                visible: strip.count === 0
                text: root.loading ? Backend.tr("Vorschaubilder werden erstellt …")
                    : root.query !== "" ? Backend.t("qs_no_results", "Nichts gefunden für „{q}“", { q: root.query })
                    : Backend.tr("Keine Hintergrundbilder gefunden")
                color: Theme.surfaceFgDim
            }
        }

        // Fußzeile: Akzentfarben + Tastenhilfe
        Item {
            x: 22
            width: parent.width - 44
            height: 34
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.tr("Akzentfarbe")
                    font.pixelSize: Theme.size.small
                    color: Theme.surfaceFgDim
                    visible: root.curColors.length > 0
                }
                Repeater {
                    model: root.curColors.slice(0, 5)
                    Rectangle {
                        id: sw

                        required property var modelData
                        required property int index
                        width: 28
                        height: 28
                        radius: 14
                        color: modelData
                        border.width: swHov.hovered ? 3 : 2
                        border.color: Theme.alpha(Theme.surfaceFg, swHov.hovered ? 0.9 : 0.25)
                        scale: swHov.hovered ? 1.15 : 1
                        Behavior on scale { Anim { curve: "spatialFast" } }
                        Txt {
                            anchors.centerIn: parent
                            text: String(sw.index + 1)
                            font.pixelSize: Theme.size.tiny
                            font.weight: Font.Bold
                            color: Theme.luminance(sw.modelData) > 0.45 ? "black" : "white"
                            opacity: 0.8
                        }
                        HoverHandler {
                            id: swHov
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pick(strip.currentIndex, sw.index, sw.modelData)
                        }
                    }
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Keycap { label: "← →"; anchors.verticalCenter: parent.verticalCenter }
                Txt { text: Backend.tr("wählen"); color: Theme.surfaceFgDim; font.pixelSize: Theme.size.small; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 8; height: 1 }
                Keycap { label: "↵"; anchors.verticalCenter: parent.verticalCenter }
                Txt { text: Backend.tr("übernehmen"); color: Theme.surfaceFgDim; font.pixelSize: Theme.size.small; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 8; height: 1 }
                Keycap { label: "1–5"; anchors.verticalCenter: parent.verticalCenter }
                Txt { text: Backend.tr("mit Akzentfarbe"); color: Theme.surfaceFgDim; font.pixelSize: Theme.size.small; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 8; height: 1 }
                Keycap { label: "Esc"; anchors.verticalCenter: parent.verticalCenter }
                Txt { text: Backend.tr("schließen"); color: Theme.surfaceFgDim; font.pixelSize: Theme.size.small; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
}
