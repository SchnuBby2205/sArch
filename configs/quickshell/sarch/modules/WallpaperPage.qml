import QtQuick
import QtQuick.Effects
import qs.components
import qs.services

// Hintergrundbild: großes Vorschau-Hero mit Ken-Burns, Karussell, Akzentfarben mit Live-Vorschau
Item {
    id: page

    required property string catName
    readonly property var category: Backend.category(catName)
    readonly property int pendingCount: 0       // wird sofort angewendet

    property var items: []
    property string dir: ""
    property string query: ""
    property string selected: ""
    property int activeIndex: 0                 // Farbindex des aktiven Wallpapers
    property var colorCache: ({})
    property var schemeCache: ({})
    property bool loading: true
    property bool thumbing: false
    property bool warming: false
    property bool applying: false
    property int hoverSwatch: -1
    property bool transOpen: false              // Panel "Übergang"
    property bool ambiOpen: false               // Panel "Ambilight"

    readonly property var shown: {
        const q = (query || Ui.search).trim().toLowerCase();
        return q === "" ? items : items.filter(w => w.name.toLowerCase().includes(q));
    }
    readonly property var colors: colorCache[selected]

    focus: true

    function load(keepSelection) {
        Backend.call(["wallpapers"], res => {
            loading = false;
            if (!res.ok)
                return;
            dir = res.dir;
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
            const want = keepSelection && selected ? selected : (res.current || (items[0]?.path ?? ""));
            Qt.callLater(() => selectPath(want, true));
            if (res.missing > 0 && !thumbing) {
                thumbing = true;
                Backend.call(["thumbs"], () => {
                    thumbing = false;
                    load(true);
                });
            }
        });
    }

    function selectPath(path, instant) {
        const i = shown.findIndex(w => w.path === path);
        if (i < 0)
            return;
        if (instant)
            carousel.positionViewAtIndex(i, ListView.Center);
        carousel.currentIndex = i;
        selected = path;
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

    function preview(i) {
        hoverSwatch = i;
        if (i < 0) {
            if (!applying) {
                Theme.preview = null;
                Theme.previewAccent = "";
            }
            return;
        }
        const hex = colors[i];
        Theme.previewAccent = hex;
        const key = `${selected}|${i}`;
        if (schemeCache[key]) {
            Theme.preview = schemeCache[key];
            return;
        }
        const path = selected;
        Backend.call(["scheme", path, String(i)], res => {
            if (!res.ok || !res.scheme || !Object.keys(res.scheme).length)
                return;
            const s = Object.assign({}, schemeCache);
            s[`${path}|${i}`] = res.scheme;
            schemeCache = s;
            if (page.hoverSwatch === i && page.selected === path)
                Theme.preview = res.scheme;
        });
    }

    function apply(i, hex) {
        if (!selected)
            return;                       // mehrfaches Klicken ist erlaubt: die letzte Wahl gewinnt
        applying = true;
        if (hex)
            Theme.previewAccent = hex;
        const path = selected;
        // Übergang sofort starten; Option "Schließen": erst das Fenster ausblenden (sonst ruckelt die
        // Ausblend-Animation, während der Übergang das große Bild lädt), dann sofort setzen
        const close = WallTrans.closeSettings;
        if (close) {
            Ui.closeRequested();
            closeApply.args = [path, i, hex || ""];
            closeApply.restart();
            return;
        }
        run(path, i, hex, false);
    }
    Timer {
        id: closeApply

        property var args: []
        interval: 320          // Ausblenden der Einstellungen (300 ms) abwarten
        onTriggered: page.run(args[0], args[1], args[2], true)
    }
    function run(path, i, hex, close) {
        WallTrans.applyWallpaper(path, i, hex || "", res => {
            if (res.superseded)
                return;                   // eine neuere Auswahl läuft noch
            applying = false;
            if (res.ok) {
                activeIndex = i;
                if (!close)
                    Ui.toast(Backend.t("wp_applied", "Hintergrundbild geändert: {name}", { name: path.split("/").pop() }), "wallpaper");
                clearPreview.restart();   // falls kein qs-colors Template läuft
            } else {
                Theme.preview = null;
                Theme.previewAccent = "";
                Ui.error(Backend.t("wp_failed", "Hintergrundbild konnte nicht gesetzt werden"), [res.error || "?"]);
            }
        });
    }

    onSelectedChanged: {
        hero.show(selected);
        fetchColors(selected);
        WallFxState.prefetch = selected;
        Theme.previewWallpaper = selected;
    }
    onShownChanged: Qt.callLater(() => selectPath(selected, true))

    Component.onCompleted: load(false)
    Component.onDestruction: {
        Theme.previewWallpaper = "";
        if (!applying) {
            Theme.preview = null;
            Theme.previewAccent = "";
        }
    }

    Timer {
        id: clearPreview

        interval: 6000
        onTriggered: {
            Theme.preview = null;
            Theme.previewAccent = "";
        }
    }

    Keys.onLeftPressed: carousel.decrementCurrentIndex()
    Keys.onRightPressed: carousel.incrementCurrentIndex()
    Keys.onReturnPressed: if (colors && colors.length)
        apply(activeIndex < colors.length ? activeIndex : 0, colors[0])

    // ── Hero ────────────────────────────────────────────────────────────────
    Item {
        id: hero

        property bool aFront: true
        property string pendingUrl: ""

        x: 4
        width: parent.width - 24
        height: parent.height - toolbar.height - carouselBox.height - 28

        function show(path) {
            const url = path ? "file://" + path : "";
            pendingUrl = url;
            const front = aFront ? imgA : imgB;
            const back = aFront ? imgB : imgA;
            if (String(front.source) === url)
                return;
            back.source = url;
            // eindeutig setzen statt umschalten: bei Cache-Treffern meldet das Bild "Ready" schon während
            // der Zuweisung (onStatusChanged hat dann bereits umgeschaltet)
            if (back.status === Image.Ready)
                aFront = back === imgA;
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.xl
            color: Theme.surfaceHigh
        }

        Item {
            id: heroContent

            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: heroMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Item {
                id: kenburns

                anchors.fill: parent

                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 1.09; duration: 16000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.09; to: 1.0; duration: 16000; easing.type: Easing.InOutSine }
                }

                Image {
                    id: imgA

                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 1800
                    opacity: hero.aFront ? 1 : 0
                    scale: hero.aFront ? 1 : 1.06
                    Behavior on opacity { Anim { curve: "standard"; duration: 550 } }
                    Behavior on scale { Anim { curve: "emphasizedDecel"; duration: 900 } }
                    onStatusChanged: if (status === Image.Ready && !hero.aFront && String(source) === hero.pendingUrl)
                        hero.aFront = true
                }
                Image {
                    id: imgB

                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 1800
                    opacity: hero.aFront ? 0 : 1
                    scale: hero.aFront ? 1.06 : 1
                    Behavior on opacity { Anim { curve: "standard"; duration: 550 } }
                    Behavior on scale { Anim { curve: "emphasizedDecel"; duration: 900 } }
                    onStatusChanged: if (status === Image.Ready && hero.aFront && String(source) === hero.pendingUrl)
                        hero.aFront = false
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                }
            }

            // Anwenden-Overlay
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                opacity: page.applying ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { Anim { curve: "effects"; duration: 300 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 14

                    Spinner {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 52
                        height: 52
                        stroke: 5
                        color: "white"
                    }
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Backend.t("wp_applying", "Hintergrundbild wird angewendet …")
                        color: "white"
                        font.pixelSize: Theme.size.label
                        font.weight: Font.Medium
                    }
                }
            }
        }

        Rectangle {
            id: heroMask

            anchors.fill: parent
            radius: Theme.radius.xl
            visible: false
            layer.enabled: true
        }

        // Titel
        Column {
            x: 28
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            width: parent.width - tray.width - 80
            spacing: 6

            Rectangle {
                readonly property bool isActive: page.selected !== "" && page.selected === Theme.wallpaper

                width: badgeRow.implicitWidth + 20
                height: 28
                radius: 14
                color: isActive ? Theme.primary : Qt.rgba(1, 1, 1, 0.18)
                Behavior on color { CAnim {} }

                Row {
                    id: badgeRow

                    anchors.centerIn: parent
                    spacing: 6

                    Icon {
                        icon: parent.parent.isActive ? "check_circle" : "visibility"
                        size: 16
                        fill: 1
                        color: parent.parent.isActive ? Theme.primaryFg : "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: parent.parent.isActive ? Backend.t("qs_wp_active", "Aktiv") : Backend.t("qs_wp_preview", "Vorschau")
                        font.pixelSize: Theme.size.small
                        font.weight: Font.DemiBold
                        color: parent.parent.isActive ? Theme.primaryFg : "white"
                    }
                }
            }
            Txt {
                id: heroTitle

                width: parent.width
                text: page.selected.split("/").pop().replace(/\.[^.]+$/, "")
                color: "white"
                font.pixelSize: Theme.size.display - 6
                font.weight: Font.Bold
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.3)

                Behavior on text {
                    SequentialAnimation {
                        ParallelAnimation {
                            Anim { target: heroTitle; property: "opacity"; to: 0; duration: 120; curve: "standard" }
                            Anim { target: heroTitle; property: "x"; to: -16; duration: 120; curve: "standard" }
                        }
                        PropertyAction {}
                        PropertyAction { target: heroTitle; property: "x"; value: 24 }
                        ParallelAnimation {
                            Anim { target: heroTitle; property: "opacity"; to: 1; curve: "effects"; duration: 300 }
                            Anim { target: heroTitle; property: "x"; to: 0; curve: "spatial" }
                        }
                    }
                }
            }
        }

        // ── Akzentfarben ──
        Rectangle {
            id: tray

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20
            width: trayCol.implicitWidth + 32
            height: trayCol.implicitHeight + 26
            radius: Theme.radius.large + 4
            color: Theme.alpha(Theme.surface, 0.72)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.1)
            Behavior on width { Anim { curve: "spatial" } }

            Column {
                id: trayCol

                anchors.centerIn: parent
                spacing: 10

                Txt {
                    text: Backend.t("wp_pick_color", "Akzentfarbe wählen")
                    font.pixelSize: Theme.size.small
                    font.weight: Font.DemiBold
                    color: Theme.surfaceFgDim
                }

                Row {
                    spacing: 10
                    height: 44

                    // lädt
                    Repeater {
                        model: page.colors === undefined ? 5 : 0

                        Rectangle {
                            required property int index

                            width: 40
                            height: 40
                            radius: 20
                            color: Theme.surfaceHighest
                            anchors.verticalCenter: parent.verticalCenter

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 90 }
                                NumberAnimation { from: 0.35; to: 1; duration: 450; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 1; to: 0.35; duration: 450; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    // Farben
                    Repeater {
                        model: page.colors ?? []

                        Rectangle {
                            id: sw

                            required property string modelData
                            required property int index
                            readonly property bool active: page.selected === Theme.wallpaper && index === page.activeIndex

                            width: 40
                            height: 40
                            radius: swArea.containsMouse ? 13 : 20
                            color: modelData
                            anchors.verticalCenter: parent.verticalCenter
                            scale: 0
                            border.width: active ? 3 : 0
                            border.color: Theme.surfaceFg
                            Behavior on radius { Anim { curve: "spatialFast" } }

                            Component.onCompleted: pop.start()
                            SequentialAnimation {
                                id: pop

                                PauseAnimation { duration: sw.index * 70 }
                                Anim { target: sw; property: "scale"; to: 1; curve: "spatialFast"; duration: 450 }
                            }

                            states: State {
                                when: swArea.containsMouse && pop.running === false
                                PropertyChanges { sw.scale: 1.16 }
                            }
                            transitions: Transition {
                                Anim { property: "scale"; curve: "spatialFast" }
                            }

                            Icon {
                                anchors.centerIn: parent
                                icon: sw.active ? "check" : "colorize"
                                size: 20
                                fill: 1
                                color: Theme.contrast(sw.modelData)
                                opacity: sw.active || swArea.containsMouse ? 1 : 0
                                Behavior on opacity { Anim { curve: "effects" } }
                            }

                            MouseArea {
                                id: swArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: page.preview(containsMouse ? sw.index : -1)
                                onClicked: page.apply(sw.index, sw.modelData)
                            }
                        }
                    }

                    // keine Farben -> Standard
                    Btn {
                        visible: page.colors !== undefined && page.colors.length === 0
                        variant: "filled"
                        icon: "format_color_reset"
                        text: Backend.t("wp_default_color", "Standardfarbe verwenden")
                        onClicked: page.apply(0, "")
                    }
                }
            }
        }
    }

    // ── Werkzeugleiste ──────────────────────────────────────────────────────
    Item {
        id: toolbar

        x: 4
        y: hero.height + 14
        width: hero.width
        height: 44

        Field {
            id: wpSearch

            width: 280
            compact: true
            icon: "search"
            placeholder: Backend.t("qs_wp_search", "Bilder filtern …")
            onEdited: page.query = text
        }

        Rectangle {
            anchors.left: wpSearch.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: counter.implicitWidth + 24
            height: 32
            radius: 16
            color: Theme.alpha(Theme.primary, 0.14)

            Txt {
                id: counter

                anchors.centerIn: parent
                text: page.shown.length ? `${carousel.currentIndex + 1} / ${page.shown.length}` : "0"
                mono: true
                font.weight: Font.Bold
                color: Theme.primary
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                visible: page.thumbing
                width: thRow.implicitWidth + 24
                height: 36
                radius: 18
                color: Theme.surfaceHigh
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: thRow

                    anchors.centerIn: parent
                    spacing: 8

                    Spinner {
                        width: 18
                        height: 18
                        stroke: 2.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: Backend.t("qs_wp_thumbs", "Vorschaubilder werden erstellt …")
                        font.pixelSize: Theme.size.small
                        color: Theme.surfaceFgDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            IconButton {
                icon: "flare"
                active: page.ambiOpen || UiPrefs.ambilight
                tooltip: Backend.tr("Ambilight")
                onClicked: {
                    page.transOpen = false;
                    page.ambiOpen = !page.ambiOpen;
                }
            }
            IconButton {
                icon: "animation"
                active: page.transOpen
                tooltip: Backend.t("qs_wp_transition", "Übergang beim Wechsel")
                onClicked: {
                    page.ambiOpen = false;
                    page.transOpen = !page.transOpen;
                }
            }
            IconButton {
                icon: "my_location"
                tooltip: Backend.t("qs_wp_goto_active", "Zum aktiven Bild")
                onClicked: page.selectPath(Theme.wallpaper, false)
            }
            IconButton {
                icon: "shuffle"
                variant: "tonal"
                tooltip: Backend.t("qs_wp_random", "Zufälliges Bild")
                onClicked: if (page.shown.length > 1) {
                    let i = carousel.currentIndex;
                    while (i === carousel.currentIndex)
                        i = Math.floor(Math.random() * page.shown.length);
                    carousel.currentIndex = i;
                }
            }
        }
    }

    // ── Karussell ───────────────────────────────────────────────────────────
    Item {
        id: carouselBox

        x: 4
        y: toolbar.y + toolbar.height + 6
        width: hero.width
        height: 178

        ListView {
            id: carousel

            readonly property int itemW: 230
            readonly property int itemH: 142

            anchors.fill: parent
            orientation: ListView.Horizontal
            spacing: 14
            clip: false
            model: page.shown
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: width / 2 - itemW / 2
            preferredHighlightEnd: width / 2 + itemW / 2
            highlightMoveDuration: 520
            highlightMoveVelocity: -1
            cacheBuffer: 1200
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: selectTimer.restart()

            Timer {
                id: selectTimer

                interval: 140
                onTriggered: {
                    const w = page.shown[carousel.currentIndex];
                    if (w)
                        page.selected = w.path;
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: e => {
                    const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x;
                    if (d < 0)
                        carousel.incrementCurrentIndex();
                    else if (d > 0)
                        carousel.decrementCurrentIndex();
                }
            }

            delegate: Item {
                id: tile

                required property var modelData
                required property int index
                readonly property bool isCurrent: ListView.isCurrentItem
                readonly property bool isActive: modelData.path === Theme.wallpaper

                width: carousel.itemW
                height: carousel.height

                Item {
                    id: frame

                    width: carousel.itemW
                    height: carousel.itemH
                    y: tile.isCurrent ? 4 : 14
                    scale: tile.isCurrent ? 1 : tileArea.containsMouse ? 0.9 : 0.84
                    opacity: tile.isCurrent ? 1 : tileArea.containsMouse ? 0.9 : 0.62
                    Behavior on y { Anim { curve: "spatial" } }
                    Behavior on scale { Anim { curve: "spatial" } }
                    Behavior on opacity { Anim { curve: "effects"; duration: 300 } }

                    // Glow
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -5
                        radius: Theme.radius.large + 5
                        color: "transparent"
                        border.width: 3
                        border.color: Theme.primary
                        opacity: tile.isCurrent ? 1 : 0
                        scale: tile.isCurrent ? 1 : 0.94
                        Behavior on opacity { Anim { curve: "effects" } }
                        Behavior on scale { Anim { curve: "spatial" } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius.large
                        color: Theme.surfaceHighest
                    }

                    RoundedImage {
                        anchors.fill: parent
                        radius: Theme.radius.large
                        source: tile.modelData.thumb ? "file://" + tile.modelData.thumb : "file://" + tile.modelData.path
                        sourceSize.width: 460
                    }

                    Rectangle {
                        visible: tile.isActive
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.primary

                        Icon {
                            anchors.centerIn: parent
                            icon: "check"
                            size: 18
                            weight: 700
                            color: Theme.primaryFg
                        }
                    }

                    MouseArea {
                        id: tileArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: carousel.currentIndex = tile.index
                    }
                }

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: frame.y + frame.height * (1 + frame.scale) / 2 + 8
                    width: carousel.itemW - 20
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.name
                    font.pixelSize: Theme.size.small
                    font.weight: tile.isCurrent ? Font.DemiBold : Font.Normal
                    color: tile.isCurrent ? Theme.surfaceFg : Theme.surfaceFgDim
                    opacity: tile.isCurrent ? 1 : 0.0
                    Behavior on opacity { Anim { curve: "effects" } }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            visible: !page.loading && page.shown.length === 0
            spacing: 8

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: "hide_image"
                size: 48
                color: Theme.surfaceFgDim
            }
            Txt {
                text: Backend.t("wp_empty", "Keine Hintergrundbilder gefunden in {dir}", { dir: page.dir })
                color: Theme.surfaceFgDim
            }
        }
    }

    // ── Panel: Übergang beim Wallpaper-Wechsel (awww) ───────────────────────
    MouseArea {
        anchors.fill: parent
        visible: page.transOpen
        z: 50
        onClicked: page.transOpen = false
    }
    Rectangle {
        id: trans

        z: 51
        width: 560
        height: transCol.implicitHeight + 36
        anchors.right: toolbar.right
        y: Math.max(4, toolbar.y - height - 8)     // klappt nach oben über das Vorschaubild auf
        radius: Theme.radius.xl
        color: Theme.alpha(Theme.surfaceContainer, 0.98)
        border.width: 1
        border.color: Theme.alpha(Theme.outline, 0.25)
        transformOrigin: Item.BottomRight
        opacity: page.transOpen ? 1 : 0
        scale: page.transOpen ? 1 : 0.9
        visible: opacity > 0
        Behavior on opacity { Anim { curve: "effects"; duration: page.transOpen ? 220 : 140 } }
        Behavior on scale { Anim { curve: page.transOpen ? "spatial" : "emphasizedAccel"; duration: page.transOpen ? 420 : 160 } }

        MouseArea {
            anchors.fill: parent     // Klicks im Panel nicht zum Schließen durchreichen
        }

        property string hoverDesc: ""

        Column {
            id: transCol

            x: 18
            y: 18
            width: parent.width - 36
            spacing: 12

            // Kopf
            Item {
                width: parent.width
                height: 36
                Row {
                    spacing: 12
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 12
                        color: Theme.secondaryContainer
                        Icon {
                            anchors.centerIn: parent
                            icon: "animation"
                            size: 20
                            color: Theme.secondaryContainerFg
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            text: Backend.t("qs_wp_transition", "Übergang beim Wechsel")
                            font.pixelSize: Theme.size.label
                            font.weight: Font.Medium
                        }
                        Txt {
                            text: trans.hoverDesc !== "" ? trans.hoverDesc : (WallTrans.types.find(t => t.id === WallTrans.type)?.desc ?? "")
                            font.pixelSize: Theme.size.tiny
                            color: Theme.surfaceFgDim
                        }
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Btn {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "play_arrow"
                        text: Backend.t("qs_wp_try", "Ausprobieren")
                        variant: "tonal"
                        h: 34
                        disabled: Theme.wallpaper === ""
                        onClicked: WallTrans.tryNow()
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "close"
                        size: 32
                        onClicked: page.transOpen = false
                    }
                }
            }

            // Effekte
            Grid {
                width: parent.width
                columns: 4
                spacing: 8

                Repeater {
                    model: WallTrans.types

                    Rectangle {
                        id: tt

                        required property var modelData
                        readonly property bool sel: WallTrans.type === modelData.id
                        width: (transCol.width - 3 * 8) / 4
                        height: 58
                        radius: sel ? 18 : 14
                        color: sel ? Theme.primaryContainer : ttArea.containsMouse ? Theme.surfaceHighest : Theme.alpha(Theme.surfaceHigh, 0.8)
                        border.width: sel ? 2 : 0
                        border.color: Theme.primary
                        Behavior on color { CAnim {} }
                        Behavior on radius { Anim { curve: "spatialFast" } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 5
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                icon: tt.modelData.icon
                                size: 24
                                fill: tt.sel || ttArea.containsMouse ? 1 : 0
                                color: tt.sel ? Theme.primaryContainerFg : Theme.surfaceFg
                                scale: ttArea.pressed ? 0.8 : ttArea.containsMouse ? 1.15 : 1
                                rotation: ttArea.containsMouse && tt.modelData.id === "random" ? 180 : 0
                                Behavior on scale { Anim { curve: "spatialFast" } }
                                Behavior on rotation { Anim { curve: "spatialSlow" } }
                            }
                            Txt {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tt.modelData.label
                                font.pixelSize: Theme.size.small
                                font.weight: tt.sel ? Font.DemiBold : Font.Normal
                                color: tt.sel ? Theme.primaryContainerFg : Theme.surfaceFgDim
                            }
                        }
                        StateLayer {
                            id: ttArea

                            radius: parent.radius
                            tint: Theme.primary
                            onClicked: WallTrans.set("type", tt.modelData.id)
                            onContainsMouseChanged: trans.hoverDesc = containsMouse ? tt.modelData.desc : ""
                        }
                    }
                }
            }

            // Dauer
            Row {
                spacing: 14
                Txt {
                    width: 110
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.t("qs_wp_duration", "Dauer")
                    color: Theme.surfaceFgDim
                }
                SSlider {
                    id: durSlider

                    width: transCol.width - 110 - 14 - 70 - 14
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0.4
                    to: 4
                    stepSize: 0.1
                    value: WallTrans.duration
                    onMoved: v => WallTrans.set("duration", v)
                    Connections {
                        target: WallTrans
                        function onDurationChanged() {
                            if (Math.abs(durSlider.value - WallTrans.duration) > 0.01)
                                durSlider.value = WallTrans.duration;
                        }
                    }
                }
                Txt {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: WallTrans.duration.toFixed(1) + " s"
                    mono: true
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            // Kurve
            Row {
                spacing: 14
                Txt {
                    width: 110
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.t("qs_wp_curve", "Verlauf")
                    color: Theme.surfaceFgDim
                }
                Segmented {
                    options: WallTrans.curves.map(c => c.id)
                    labels: WallTrans.curves.map(c => c.label)
                    value: WallTrans.bezier
                    segWidth: (transCol.width - 124 - 10) / 4
                    onPicked: v => WallTrans.set("bezier", v)
                }
            }

            // Mauszeiger
            Row {
                spacing: 14
                opacity: ["random", "grow", "outer"].indexOf(WallTrans.type) >= 0 ? 1 : 0.4
                Txt {
                    width: 110
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.t("qs_wp_cursor", "Am Mauszeiger")
                    color: Theme.surfaceFgDim
                }
                Segmented {
                    options: ["false", "true"]
                    labels: [Backend.t("qs_off", "Aus"), Backend.t("qs_on", "An")]
                    value: String(WallTrans.cursor)
                    segWidth: 90
                    onPicked: v => WallTrans.set("cursor", v === "true")
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.tr("Kreis öffnet sich dort, wo die Maus ist")
                    font.pixelSize: Theme.size.tiny
                    color: Theme.surfaceFgDim
                }
            }

            // Einstellungen nach der Wahl schließen
            Row {
                spacing: 14
                Txt {
                    width: 110
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.tr("Schließen")
                    color: Theme.surfaceFgDim
                }
                Segmented {
                    options: ["false", "true"]
                    labels: [Backend.t("qs_off", "Aus"), Backend.t("qs_on", "An")]
                    value: String(WallTrans.closeSettings)
                    segWidth: 90
                    onPicked: v => WallTrans.set("closeSettings", v === "true")
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.tr("Fenster schließt vor dem Übergang")
                    font.pixelSize: Theme.size.tiny
                    color: Theme.surfaceFgDim
                }
            }

        }
    }

    // ── Panel: Ambilight (Leuchten in den Wallpaper-Farben rund um die Fenster) ─────────
    MouseArea {
        anchors.fill: parent
        visible: page.ambiOpen
        z: 50
        onClicked: page.ambiOpen = false
    }
    Rectangle {
        id: ambiPanel

        z: 51
        width: 520
        height: ambiCol.implicitHeight + 36
        anchors.right: toolbar.right
        y: Math.max(4, toolbar.y - height - 8)
        radius: Theme.radius.xl
        color: Theme.alpha(Theme.surfaceContainer, 0.98)
        border.width: 1
        border.color: Theme.alpha(Theme.outline, 0.25)
        transformOrigin: Item.BottomRight
        opacity: page.ambiOpen ? 1 : 0
        scale: page.ambiOpen ? 1 : 0.9
        visible: opacity > 0
        Behavior on opacity { Anim { curve: "effects"; duration: page.ambiOpen ? 220 : 140 } }
        Behavior on scale { Anim { curve: page.ambiOpen ? "spatial" : "emphasizedAccel"; duration: page.ambiOpen ? 420 : 160 } }

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: ambiCol

            x: 18
            y: 18
            width: parent.width - 36
            spacing: 14

            Item {
                width: parent.width
                height: 36
                Row {
                    spacing: 12
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 12
                        color: Theme.secondaryContainer
                        Icon {
                            anchors.centerIn: parent
                            icon: "flare"
                            size: 20
                            color: Theme.secondaryContainerFg
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            text: Backend.tr("Ambilight")
                            font.pixelSize: Theme.size.label
                            font.weight: Font.Medium
                        }
                        Txt {
                            text: Backend.tr("Leuchten in den Wallpaper-Farben rund um die Fenster")
                            font.pixelSize: Theme.size.tiny
                            color: Theme.surfaceFgDim
                        }
                    }
                }
                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    size: 34
                    onClicked: page.ambiOpen = false
                }
            }

            Row {
                spacing: 14
                Txt {
                    width: 110
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.tr("Ambilight")
                    color: Theme.surfaceFgDim
                }
                Segmented {
                    options: ["false", "true"]
                    labels: [Backend.t("qs_off", "Aus"), Backend.t("qs_on", "An")]
                    value: String(UiPrefs.ambilight)
                    segWidth: 90
                    onPicked: v => UiPrefs.set("ambilight", v === "true")
                }
            }

            Repeater {
                model: [
                    { key: "ambilightStrength", label: Backend.tr("Stärke"), from: 0.1, to: 1, step: 0.05, pct: true },
                    { key: "ambilightSize", label: Backend.tr("Ausdehnung"), from: 0.5, to: 2, step: 0.1, pct: true }
                ]
                Row {
                    id: ar

                    required property var modelData
                    spacing: 14
                    opacity: UiPrefs.ambilight ? 1 : 0.4
                    Txt {
                        width: 110
                        anchors.verticalCenter: parent.verticalCenter
                        text: ar.modelData.label
                        color: Theme.surfaceFgDim
                    }
                    SSlider {
                        id: ambSlider

                        width: ambiCol.width - 110 - 14 - 70 - 14
                        anchors.verticalCenter: parent.verticalCenter
                        from: ar.modelData.from
                        to: ar.modelData.to
                        stepSize: ar.modelData.step
                        value: UiPrefs[ar.modelData.key]
                        onMoved: v => UiPrefs.set(ar.modelData.key, v)
                        Connections {
                            target: UiPrefs
                            function onAmbilightStrengthChanged() { ambSlider.sync(); }
                            function onAmbilightSizeChanged() { ambSlider.sync(); }
                        }
                        function sync() {
                            if (Math.abs(value - UiPrefs[ar.modelData.key]) > 0.001)
                                value = UiPrefs[ar.modelData.key];
                        }
                    }
                    Txt {
                        width: 70
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(UiPrefs[ar.modelData.key] * 100) + " %"
                        mono: true
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }
            }
        }
    }
}
