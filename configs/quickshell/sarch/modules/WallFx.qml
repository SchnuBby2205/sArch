import QtQuick
import qs.services

// Animation für eigene Wallpaper-Übergänge (ein Bildschirm).
//  slice: altes Bild in schräge Streifen geschnitten, abwechselnd nach rechts oben / links unten weg
//  flip:  altes Bild als Kacheln, die in einer Welle umklappen – Rückseite zeigt das neue Bild
Item {
    id: fx

    property string oldSrc: WallFxState.oldSrc
    property string newSrc: WallFxState.newSrc
    property string mode: WallFxState.mode
    property real duration: WallFxState.duration
    property int token: WallFxState.token
    // Bildschirmgröße (das Fenster ist vor dem ersten Einblenden noch 0×0 groß)
    property real screenW: 1920
    property real screenH: 1080
    readonly property real sw: width > 0 ? width : screenW
    readonly property real sh: height > 0 ? height : screenH
    // Kacheln erst anlegen, wenn die Bilder im Cache sind (sonst dekodiert jede Kachel synchron)
    readonly property bool showTiles: WallFxState.active || !autoRun

    // Bilder vorab im Hintergrund dekodieren – gleicher Cache-Schlüssel (Quelle + Größe) wie die Kacheln
    Image {
        id: preOld

        visible: false
        asynchronous: true
        cache: true
        // ohne laufenden Übergang: das aktuelle Wallpaper warm halten (ist beim nächsten Wechsel das "alte")
        source: fx.oldSrc !== "" && (WallFxState.preparing || WallFxState.active) ? fx.oldSrc : WallFxState.url(Theme.wallpaper)
        sourceSize.width: fx.sw
        sourceSize.height: fx.sh
    }
    Image {
        id: preNew

        visible: false
        asynchronous: true
        cache: true
        source: (WallFxState.preparing || WallFxState.active) ? (fx.mode === "flip" ? fx.newSrc : "") : WallFxState.url(WallFxState.prefetch)
        sourceSize.width: fx.sw
        sourceSize.height: fx.sh
    }
    function done(img) {
        return img.status === Image.Ready || img.status === Image.Error || String(img.source) === "";
    }
    readonly property bool loaded: String(preOld.source) === oldSrc && done(preOld)
        && (mode !== "flip" || (String(preNew.source) === newSrc && done(preNew)))
    onLoadedChanged: report()
    function report() {
        if (autoRun && loaded && WallFxState.preparing)
            WallFxState.ready(token);
    }

    // Fortschritt 0..1 (im Test direkt setzbar)
    property real t: 0
    property bool autoRun: true
    NumberAnimation on t {
        id: run

        running: false
        from: 0
        to: 1
        duration: fx.duration * 1000
    }
    onTokenChanged: if (autoRun) {
        t = 0;
        run.stop();
        Qt.callLater(report);          // Bilder können schon im Cache sein
    }
    Connections {
        target: WallFxState
        function onActiveChanged() {
            if (WallFxState.active && fx.autoRun) {
                fx.t = 0;
                startDelay.restart();
            }
        }
    }
    // erst loslegen, wenn awww das neue Bild darunter gesetzt hat (WallFxState: swap nach 70 ms)
    Timer {
        id: startDelay

        interval: 120
        onTriggered: run.restart()
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }
    function easeInBack(p) {
        const c1 = 1.4, c3 = c1 + 1;
        return c3 * p * p * p - c1 * p * p;
    }
    function easeInOutCubic(p) {
        return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2;
    }

    // ── Zerschneiden ────────────────────────────────────────────────────────
    Item {
        id: slice

        visible: fx.mode === "slice"
        anchors.fill: parent

        readonly property real angle: 32                      // Neigung der Schnitte
        readonly property real diag: Math.ceil(Math.sqrt(fx.width * fx.width + fx.height * fx.height)) + 40
        readonly property int count: 14
        readonly property real sw: diag / count

        Item {
            id: rot

            width: slice.diag
            height: slice.diag
            x: (fx.width - width) / 2
            y: (fx.height - height) / 2
            rotation: slice.angle

            Repeater {
                model: slice.visible && fx.showTiles ? slice.count : 0

                Item {
                    id: strip

                    required property int index
                    readonly property int dir: index % 2 === 0 ? -1 : 1        // -1: rechts oben, +1: links unten
                    readonly property real delay: (index / (slice.count - 1)) * 0.35
                    readonly property real p: fx.clamp01((fx.t - delay) / 0.65)
                    readonly property real e: fx.easeInBack(p)

                    x: index * slice.sw
                    width: Math.ceil(slice.sw) + 1
                    height: slice.diag
                    clip: true
                    opacity: 1 - Math.max(0, p - 0.75) * 4
                    transform: Translate {
                        y: strip.dir * strip.e * slice.diag * 1.05
                    }

                    // Schnittkante: feiner Schatten
                    Rectangle {
                        z: 2
                        width: 2
                        height: parent.height
                        color: "black"
                        opacity: 0.25 * Math.min(1, strip.p * 6)
                    }

                    Item {
                        x: -strip.x
                        width: slice.diag
                        height: slice.diag

                        Image {
                            width: fx.width
                            height: fx.height
                            x: (slice.diag - width) / 2
                            y: (slice.diag - height) / 2
                            rotation: -slice.angle
                            source: fx.oldSrc
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: fx.sw
                            sourceSize.height: fx.sh
                            cache: true
                            asynchronous: false            // kommt aus dem Cache (vorab geladen)
                            smooth: true
                        }
                    }
                }
            }
        }
    }

    // ── Kacheln umklappen ───────────────────────────────────────────────────
    Item {
        id: flip

        visible: fx.mode === "flip"
        anchors.fill: parent

        readonly property int cols: 12
        readonly property int rows: Math.max(4, Math.round(cols * fx.height / Math.max(1, fx.width)))
        readonly property real tw: fx.width / cols
        readonly property real th: fx.height / rows

        Repeater {
            model: flip.visible && fx.showTiles ? flip.cols * flip.rows : 0

            Flipable {
                id: tile

                required property int index
                readonly property int c: index % flip.cols
                readonly property int r: Math.floor(index / flip.cols)
                // Welle diagonal von links oben nach rechts unten
                readonly property real delay: ((c + r) / (flip.cols + flip.rows - 2)) * 0.5
                readonly property real p: fx.clamp01((fx.t - delay) / 0.5)
                readonly property real e: fx.easeInOutCubic(p)

                x: c * flip.tw
                y: r * flip.th
                width: Math.ceil(flip.tw) + 1
                height: Math.ceil(flip.th) + 1
                scale: 1 - 0.22 * Math.sin(Math.PI * e)
                z: p > 0 && p < 1 ? 2 : 1

                transform: Rotation {
                    origin.x: tile.width / 2
                    origin.y: tile.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: 180 * tile.e
                }

                front: Item {
                    width: tile.width
                    height: tile.height
                    clip: true
                    Image {
                        x: -tile.x
                        y: -tile.y
                        width: fx.width
                        height: fx.height
                        source: fx.oldSrc
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: fx.sw
                        sourceSize.height: fx.sh
                        cache: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                        opacity: 0.35 * Math.sin(Math.PI * tile.e)
                    }
                }
                back: Item {
                    width: tile.width
                    height: tile.height
                    clip: true
                    Image {
                        x: -tile.x
                        y: -tile.y
                        width: fx.width
                        height: fx.height
                        source: fx.newSrc
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: fx.sw
                        sourceSize.height: fx.sh
                        cache: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                        opacity: 0.35 * Math.sin(Math.PI * tile.e)
                    }
                }
            }
        }
    }
}
