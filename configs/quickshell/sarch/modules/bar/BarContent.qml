import QtQuick
import QtQuick.Effects
import qs.components
import qs.services

// Inhalt der Bar als "Streifen" entlang einer Bildschirmkante.
// Größe: horizontal = volle Breite × (size + margin), vertikal entsprechend.
// Wird von der echten Bar und von der Live-Vorschau in den Einstellungen benutzt.
Item {
    id: root

    property var cfg: BarConfig.current
    property var screen: null
    property bool preview: false
    property bool shown: true             // Ein-/Ausfahren (Positionswechsel, Start)
    property alias barItem: bar

    readonly property string pos: cfg.position
    readonly property bool vertical: pos === "left" || pos === "right"
    readonly property string style: cfg.style
    readonly property real thick: cfg.size
    readonly property real gap: style === "docked" ? 0 : cfg.margin
    readonly property real radius: style === "docked" ? 0 : cfg.radius
    readonly property real stripThickness: thick + gap
    readonly property color bgColor: Theme.alpha(Theme.surface, cfg.opacity)

    // Rahmen der eigentlichen Bar innerhalb des Streifens
    readonly property real along: vertical ? height : width
    readonly property real barStart: style === "docked" ? 0 : gap
    readonly property real barLen: along - 2 * barStart

    // Einfahr-Animation: 0 = versteckt (über die Kante hinaus), 1 = sichtbar
    property real reveal: shown ? 1 : 0
    Behavior on reveal { Anim { curve: root.shown ? "spatialSlow" : "emphasizedAccel"; duration: root.shown ? 750 : 260 } }

    readonly property real hideOffset: (1 - reveal) * (stripThickness + 24)

    function modulesIn(zone) {
        return (cfg.modules || []).filter(m => m.zone === zone).map(m => m.id).join(",");
    }
    readonly property string startIds: modulesIn("start")
    readonly property string centerIds: modulesIn("center")
    readonly property string endIds: modulesIn("end")

    Item {
        id: bar

        // Position der Bar im Streifen (Abstand zur Kante = gap)
        x: root.vertical ? (root.pos === "left" ? root.gap : 0) : root.barStart
        y: root.vertical ? root.barStart : (root.pos === "top" ? root.gap : 0)
        width: root.vertical ? root.thick : root.barLen
        height: root.vertical ? root.barLen : root.thick
        opacity: root.reveal

        Behavior on x { Anim { curve: "spatial" } }
        Behavior on y { Anim { curve: "spatial" } }
        Behavior on width { Anim { curve: "spatial" } }
        Behavior on height { Anim { curve: "spatial" } }

        transform: Translate {
            x: root.pos === "left" ? -root.hideOffset : root.pos === "right" ? root.hideOffset : 0
            y: root.pos === "top" ? -root.hideOffset : root.pos === "bottom" ? root.hideOffset : 0
        }

        // ── Hintergrund (floating / docked) ──
        Rectangle {
            id: mainBg

            anchors.fill: parent
            radius: root.radius
            color: root.bgColor
            border.width: 1
            border.color: Theme.alpha(Theme.outline, 0.16)
            opacity: root.style === "islands" ? 0 : 1
            Behavior on opacity { Anim { curve: "effects"; duration: 350 } }
            Behavior on radius { Anim { curve: "spatial" } }

            // feiner Akzent-Glanz entlang der Innenkante
            Rectangle {
                visible: root.style !== "docked"
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, parent.radius - 1)
                color: "transparent"
                border.width: 1
                border.color: Theme.alpha(Theme.primary, 0.08)
            }
        }
        // docked: nur eine Linie zur Bildschirmmitte hin
        Rectangle {
            visible: root.style === "docked"
            color: Theme.alpha(Theme.primary, 0.25)
            width: root.vertical ? 1 : parent.width
            height: root.vertical ? parent.height : 1
            x: root.pos === "left" ? parent.width - 1 : 0
            y: root.pos === "top" ? parent.height - 1 : 0
        }

        // ── Zonen ──
        BarZone {
            id: zStart

            zone: "start"
            ids: root.startIds
            host: root
            order: 0
            x: root.vertical ? 0 : pad
            y: root.vertical ? pad : 0
            readonly property real pad: root.style === "islands" ? 0 : 6
        }
        BarZone {
            id: zCenter

            zone: "center"
            ids: root.centerIds
            host: root
            order: 1
            x: root.vertical ? 0 : (bar.width - width) / 2
            y: root.vertical ? (bar.height - height) / 2 : 0
        }
        BarZone {
            id: zEnd

            zone: "end"
            ids: root.endIds
            host: root
            order: 2
            x: root.vertical ? 0 : bar.width - width - pad
            y: root.vertical ? bar.height - height - pad : 0
            readonly property real pad: root.style === "islands" ? 0 : 6
        }
    }
}
