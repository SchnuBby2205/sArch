import QtQuick
import QtQuick.Controls
import qs.components
import qs.services
import qs.modules.bar

// Einstellungen der Bar: Live-Vorschau (Kante anklicken), Stil, Maße, Module & Zonen
Item {
    id: bp

    required property string catName
    readonly property var category: Backend.category(catName)

    property var original: BarConfig.current
    property var draft: BarConfig.current
    property bool busy: false
    property bool loaded: false
    readonly property int pendingCount: loaded ? diffCount(original, draft) : 0
    readonly property bool vertical: draft.position === "left" || draft.position === "right"

    focus: true

    function clone(o) {
        return JSON.parse(JSON.stringify(o));
    }

    function diffCount(a, b) {
        if (typeof a !== "object" || a === null || typeof b !== "object" || b === null)
            return JSON.stringify(a) === JSON.stringify(b) ? 0 : 1;
        if (Array.isArray(a) || Array.isArray(b)) {
            if (!Array.isArray(a) || !Array.isArray(b))
                return 1;
            let n = Math.abs(a.length - b.length);
            for (let i = 0; i < Math.min(a.length, b.length); i++)
                n += JSON.stringify(a[i]) === JSON.stringify(b[i]) ? 0 : 1;
            return n;
        }
        let n = 0;
        const keys = new Set(Object.keys(a).concat(Object.keys(b)));
        for (const k of keys)
            n += diffCount(a[k], b[k]);
        return n;
    }

    // set("clock.seconds", true)
    function set(path, value) {
        const d = clone(draft);
        const parts = path.split(".");
        let o = d;
        for (let i = 0; i < parts.length - 1; i++) {
            if (typeof o[parts[i]] !== "object" || o[parts[i]] === null)
                o[parts[i]] = {};
            o = o[parts[i]];
        }
        o[parts[parts.length - 1]] = value;
        draft = d;
    }

    function setZone(id, zone) {
        const d = clone(draft);
        const m = d.modules.find(x => x.id === id);
        if (m)
            m.zone = zone;
        draft = d;
    }

    // innerhalb der Gesamtliste verschieben (wirkt auf die Reihenfolge in der Zone)
    function move(id, dir) {
        const d = clone(draft);
        const i = d.modules.findIndex(x => x.id === id);
        const j = i + dir;
        if (i < 0 || j < 0 || j >= d.modules.length)
            return;
        const t = d.modules[i];
        d.modules[i] = d.modules[j];
        d.modules[j] = t;
        draft = d;
    }

    function load() {
        Backend.call(["bar"], res => {
            const cfg = BarConfig.merge(BarConfig.defaults, res.ok ? res.config : {});
            original = clone(cfg);
            draft = clone(cfg);
            loaded = true;
        });
    }

    function reset() {
        draft = clone(original);
    }

    function apply() {
        if (busy || pendingCount === 0)
            return;
        busy = true;
        Backend.call(["apply-bar", Backend.json(draft)], res => {
            busy = false;
            if (res.ok) {
                original = clone(draft);
                BarConfig.reload();
                Ui.toast(Backend.t("qs_bar_applied", "Leiste aktualisiert"), "toolbar");
            } else {
                Ui.error(Backend.t("error_heading", "Fehler beim Schreiben"), res.errors || [res.error]);
            }
        });
    }

    Component.onCompleted: load()

    Connections {
        target: Ui
        function onRequestApply() {
            bp.apply();
        }
        function onRequestReset() {
            bp.reset();
        }
    }

    readonly property var edgeNames: ({
        top: Backend.t("qs_bar_top", "Oben"),
        bottom: Backend.t("qs_bar_bottom", "Unten"),
        left: Backend.t("qs_bar_left", "Links"),
        right: Backend.t("qs_bar_right", "Rechts")
    })

    Flickable {
        id: flick

        anchors.fill: parent
        contentHeight: col.height + 120
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            id: sb

            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: Theme.alpha(Theme.surfaceFgDim, sb.pressed ? 0.6 : sb.hovered ? 0.45 : 0.25)
            }
            background: null
        }

        Column {
            id: col

            x: 4
            width: flick.width - 28
            spacing: 14

            // ── Live-Vorschau ─────────────────────────────────────────────
            Card {
                id: previewCard

                width: parent.width
                height: monitor.height + 70
                order: 0

                Txt {
                    x: 22
                    y: 16
                    text: Backend.t("qs_bar_preview", "Live-Vorschau")
                    font.pixelSize: Theme.size.label
                    font.weight: Font.Medium
                }
                Txt {
                    anchors.right: parent.right
                    anchors.rightMargin: 22
                    y: 18
                    text: Backend.t("qs_bar_preview_hint", "Kante anklicken, um die Leiste dort anzudocken")
                    font.pixelSize: Theme.size.small
                    color: Theme.surfaceFgDim
                }

                // Monitor
                Item {
                    id: monitor

                    readonly property real virtW: 1600
                    readonly property real virtH: 900
                    readonly property real s: width / virtW

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 48
                    width: Math.min(parent.width - 44, 760)
                    height: width * virtH / virtW

                    // Rahmen
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -6
                        radius: 18
                        color: Theme.surfaceLowest
                        border.width: 1
                        border.color: Theme.alpha(Theme.outline, 0.3)
                    }

                    RoundedImage {
                        anchors.fill: parent
                        radius: 12
                        source: Theme.wallpaper !== "" ? "file://" + Theme.wallpaper : ""
                        sourceSize.width: 1000
                    }

                    // virtueller Bildschirm in Originalgröße, herunterskaliert
                    Item {
                        id: virt

                        width: monitor.virtW
                        height: monitor.virtH
                        scale: monitor.s
                        transformOrigin: Item.TopLeft
                        clip: true

                        BarContent {
                            id: previewBar

                            cfg: bp.draft
                            preview: true
                            readonly property real strip: bp.draft.size + (bp.draft.style === "docked" ? 0 : bp.draft.margin)
                            x: bp.draft.position === "right" ? virt.width - strip : 0
                            y: bp.draft.position === "bottom" ? virt.height - strip : 0
                            width: vertical ? strip : virt.width
                            height: vertical ? virt.height : strip
                        }

                        // angedeutetes Fenster, das der Leiste Platz macht
                        Rectangle {
                            readonly property real strip: previewBar.strip + 10
                            x: (bp.draft.position === "left" ? strip : 0) + 40
                            y: (bp.draft.position === "top" ? strip : 0) + 40
                            width: virt.width - 80 - (bp.vertical ? strip : 0)
                            height: virt.height - 80 - (bp.vertical ? 0 : strip)
                            radius: 14
                            color: Theme.alpha(Theme.surface, 0.55)
                            border.width: 2
                            border.color: Theme.alpha(Theme.primary, 0.5)
                            Behavior on x { Anim { curve: "spatial" } }
                            Behavior on y { Anim { curve: "spatial" } }
                            Behavior on width { Anim { curve: "spatial" } }
                            Behavior on height { Anim { curve: "spatial" } }

                            Row {
                                x: 18
                                y: 16
                                spacing: 8
                                Repeater {
                                    model: [Theme.error, Theme.tertiary, Theme.primary]
                                    Rectangle {
                                        required property color modelData
                                        width: 14
                                        height: 14
                                        radius: 7
                                        color: modelData
                                        opacity: 0.8
                                    }
                                }
                            }
                        }
                    }

                    // Kanten zum Anklicken
                    Repeater {
                        model: ["top", "bottom", "left", "right"]

                        Item {
                            id: edgeHot

                            required property string modelData
                            readonly property bool horiz: modelData === "top" || modelData === "bottom"
                            readonly property bool current: bp.draft.position === modelData
                            readonly property real t: 34

                            x: modelData === "right" ? monitor.width - t : 0
                            y: modelData === "bottom" ? monitor.height - t : 0
                            width: horiz ? monitor.width : t
                            height: horiz ? t : monitor.height
                            z: 5

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 10
                                color: Theme.alpha(Theme.primary, edgeArea.containsMouse && !edgeHot.current ? 0.35 : 0)
                                border.width: edgeArea.containsMouse && !edgeHot.current ? 2 : 0
                                border.color: Theme.primary
                                Behavior on color { CAnim {} }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    opacity: edgeArea.containsMouse && !edgeHot.current ? 1 : 0
                                    Behavior on opacity { Anim { curve: "effects" } }

                                    Icon {
                                        icon: edgeHot.modelData === "top" ? "vertical_align_top" : edgeHot.modelData === "bottom" ? "vertical_align_bottom" : edgeHot.modelData === "left" ? "align_horizontal_left" : "align_horizontal_right"
                                        size: 18
                                        fill: 1
                                        color: Theme.primaryFg
                                    }
                                    Txt {
                                        visible: edgeHot.horiz
                                        text: bp.edgeNames[edgeHot.modelData]
                                        font.weight: Font.Bold
                                        color: Theme.primaryFg
                                    }
                                }
                            }

                            MouseArea {
                                id: edgeArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: edgeHot.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: bp.set("position", edgeHot.modelData)
                            }
                        }
                    }
                }
            }

            // ── Position & Stil ───────────────────────────────────────────
            Grid {
                id: optGrid

                width: parent.width
                columns: width > 820 ? 2 : 1
                columnSpacing: 14
                rowSpacing: 14

                readonly property real cw: (width - (columns - 1) * columnSpacing) / columns

                ChoiceCard {
                    width: optGrid.cw
                    order: 1
                    icon: "open_with"
                    title: Backend.t("qs_bar_position", "Position")
                    options: ["top", "bottom", "left", "right"]
                    labels: [bp.edgeNames.top, bp.edgeNames.bottom, bp.edgeNames.left, bp.edgeNames.right]
                    value: bp.draft.position
                    modified: bp.draft.position !== bp.original.position
                    onPicked: v => bp.set("position", v)
                }
                ChoiceCard {
                    width: optGrid.cw
                    order: 2
                    icon: "style"
                    title: Backend.t("qs_bar_style", "Stil")
                    options: ["islands", "floating", "docked"]
                    labels: [Backend.t("qs_bar_islands", "Inseln"), Backend.t("qs_bar_floating", "Schwebend"), Backend.t("qs_bar_docked", "Angedockt")]
                    value: bp.draft.style
                    modified: bp.draft.style !== bp.original.style
                    onPicked: v => bp.set("style", v)
                }
                SliderCard {
                    width: optGrid.cw
                    order: 3
                    icon: "height"
                    title: Backend.t("qs_bar_size", "Größe")
                    from: 30; to: 64; stepSize: 1; suffix: " px"
                    value: bp.draft.size
                    original: bp.original.size
                    onMoved: v => bp.set("size", v)
                }
                SliderCard {
                    width: optGrid.cw
                    order: 4
                    icon: "padding"
                    title: Backend.t("qs_bar_margin", "Abstand zum Rand")
                    from: 0; to: 24; stepSize: 1; suffix: " px"
                    enabled: bp.draft.style !== "docked"
                    opacity: enabled ? 1 : 0.45
                    value: bp.draft.margin
                    original: bp.original.margin
                    onMoved: v => bp.set("margin", v)
                }
                SliderCard {
                    width: optGrid.cw
                    order: 5
                    icon: "rounded_corner"
                    title: Backend.t("qs_bar_radius", "Rundung")
                    from: 0; to: 32; stepSize: 1; suffix: " px"
                    enabled: bp.draft.style !== "docked"
                    opacity: enabled ? 1 : 0.45
                    value: bp.draft.radius
                    original: bp.original.radius
                    onMoved: v => bp.set("radius", v)
                }
                SliderCard {
                    width: optGrid.cw
                    order: 6
                    icon: "opacity"
                    title: Backend.t("qs_bar_opacity", "Deckkraft")
                    from: 0; to: 100; stepSize: 1; suffix: " %"
                    value: Math.round(bp.draft.opacity * 100)
                    original: Math.round(bp.original.opacity * 100)
                    onMoved: v => bp.set("opacity", v / 100)
                }
            }

            // ── Module ────────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 50

                Column {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Txt {
                        text: Backend.t("qs_bar_modules", "Module")
                        font.pixelSize: Theme.size.title
                        font.weight: Font.DemiBold
                        color: Theme.primary
                    }
                    Txt {
                        text: Backend.t("qs_bar_modules_hint", "Zone wählen (Aus = ausgeblendet) · Pfeile ändern die Reihenfolge")
                        font.pixelSize: Theme.size.small
                        color: Theme.surfaceFgDim
                    }
                }
            }

            Item {
                id: modList

                width: parent.width
                height: {
                    let h = 0;
                    for (let i = 0; i < modRep.count; i++) {
                        const it = modRep.itemAt(i);
                        if (it)
                            h += it.height + 10;
                    }
                    return h;
                }

                // y-Position eines Moduls = Summe der Höhen der Module davor (animiert)
                function yFor(id) {
                    let y = 0;
                    for (const m of bp.draft.modules) {
                        if (m.id === id)
                            return y;
                        const idx = BarConfig.catalog.findIndex(c => c.id === m.id);
                        const it = modRep.itemAt(idx);
                        if (it)
                            y += it.height + 10;
                    }
                    return y;
                }

                Repeater {
                    id: modRep

                    model: BarConfig.catalog

                    ModuleCard {
                        required property var modelData
                        required property int index

                        info: modelData
                        page: bp
                        order: 7 + index
                        width: modList.width
                        y: modList.yFor(modelData.id)
                        Behavior on y { Anim { curve: "spatial" } }
                    }
                }
            }
        }
    }

    // ── kleine Karten-Komponenten ─────────────────────────────────────────
    component CardHead: Row {
        property string icon
        property string title
        property bool modified: false

        spacing: 12

        Rectangle {
            width: 36
            height: 36
            radius: 12
            color: Theme.secondaryContainer
            Icon {
                anchors.centerIn: parent
                icon: parent.parent.icon
                size: 20
                color: Theme.secondaryContainerFg
            }
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.title
            font.pixelSize: Theme.size.label
            font.weight: Font.Medium
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: Theme.tertiary
            scale: parent.modified ? 1 : 0
            Behavior on scale { Anim { curve: "spatialFast" } }
        }
    }

    component ChoiceCard: Card {
        id: cc

        property string icon
        property string title
        property var options: []
        property var labels: []
        property string value
        property bool modified: false
        signal picked(string v)

        height: 120
        highlighted: modified

        CardHead {
            x: 18
            y: 16
            icon: cc.icon
            title: cc.title
            modified: cc.modified
        }
        Segmented {
            x: 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            options: cc.options
            labels: cc.labels
            value: cc.value
            segWidth: (cc.width - 44) / Math.max(1, cc.options.length)
            onPicked: v => cc.picked(v)
        }
    }

    component SliderCard: Card {
        id: sc

        property string icon
        property string title
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property string suffix: ""
        property real value: 0
        property real original: 0
        signal moved(real v)

        height: 120
        highlighted: value !== original

        CardHead {
            x: 18
            y: 16
            icon: sc.icon
            title: sc.title
            modified: sc.value !== sc.original
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 18
            y: 18
            width: vt.implicitWidth + 22
            height: 32
            radius: 16
            color: sc.value !== sc.original ? Theme.tertiaryContainer : Theme.surfaceHighest
            Txt {
                id: vt
                anchors.centerIn: parent
                text: Math.round(sc.value) + sc.suffix
                mono: true
                font.weight: Font.Bold
                color: sc.value !== sc.original ? Theme.tertiaryContainerFg : Theme.surfaceFg
            }
        }
        SSlider {
            id: sl

            x: 18
            width: sc.width - 36
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            from: sc.from
            to: sc.to
            stepSize: sc.stepSize
            suffix: sc.suffix
            value: sc.value
            onMoved: v => sc.moved(v)
            Connections {
                target: sc
                function onValueChanged() {
                    if (sl.value !== sc.value)
                        sl.value = sc.value;
                }
            }
        }
    }
}
