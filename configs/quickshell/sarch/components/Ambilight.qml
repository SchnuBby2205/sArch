import QtQuick
import QtQuick.Effects
import qs.services

// Ambilight: weiches Leuchten in den Farben des Wallpapers rund um ein Panel.
// Das (stark verkleinerte) Wallpaper wird auf Panelgröße gelegt und so stark geblurrt, dass es
// über die Kanten hinaus ausläuft – jede Seite leuchtet in den Farben, die das Bild dort hat.
// Ein-/Ausschalten und Stärke: Einstellungen → Hintergrund → Ambilight (services/UiPrefs.qml)
Item {
    id: root

    property string source: Theme.wallpaper           // Pfad (ohne file://)
    property real radius: Theme.radius.xl
    readonly property bool on: UiPrefs.ambilight && source !== ""

    visible: opacity > 0.01
    opacity: on ? UiPrefs.ambilightStrength : 0
    Behavior on opacity { Anim { curve: "effects"; duration: 500 } }

    Item {
        id: src

        anchors.fill: parent
        visible: false

        Image {
            anchors.fill: parent
            // etwas größer, damit an den Rändern die Farben vom Bildrand mitkommen
            anchors.margins: -24
            source: root.source !== "" ? "file://" + root.source : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 320                       // klein reicht – wird ohnehin weichgezeichnet
            asynchronous: true
            cache: true
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: src
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        blurMultiplier: 1.2 + 2.2 * UiPrefs.ambilightSize
        saturation: 0.55
        brightness: 0.12
        scale: 1 + 0.06 * UiPrefs.ambilightSize          // leicht über das Panel hinaus
    }
}
