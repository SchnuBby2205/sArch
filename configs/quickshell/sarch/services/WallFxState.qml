pragma Singleton

import QtQuick
import Quickshell

// Eigene Wallpaper-Übergänge (die awww nicht kann): "slice" (Zerschneiden) und "flip" (Kacheln).
// Ablauf: Über dem Wallpaper liegt kurz ein Fenster mit dem ALTEN Bild, darunter setzt awww sofort
// das NEUE; dann wird das alte Bild animiert weggeräumt. Aufruf: bin/sarch_wallpaper_set.sh -> IPC.
Singleton {
    id: root

    property bool active: false          // Overlay sichtbar
    property bool preparing: false       // Bilder werden (im Hintergrund) dekodiert
    property string oldSrc: ""
    property string newSrc: ""
    property string newPath: ""
    property string mode: "slice"
    property real duration: 1.6
    property int token: 0
    property string prefetch: ""         // wahrscheinliches nächstes Bild (Picker/Einstellungen) vorab dekodieren

    function url(p) {
        return p === "" ? "" : p.startsWith("file://") ? p : "file://" + p;
    }
    function start(oldImg, newImg, type, dur) {
        oldSrc = url(oldImg);
        newSrc = url(newImg);
        newPath = newImg;
        mode = type === "flip" ? "flip" : "slice";
        duration = Math.max(0.4, Math.min(6, Number(dur) || 1.6));
        token += 1;
        active = false;
        preparing = true;                 // WallFx meldet ready(), sobald die Bilder dekodiert sind
        prepTimeout.restart();
    }
    // Bilder sind geladen: Overlay zeigen, darunter das neue Bild setzen, Animation läuft an
    function ready(tok) {
        if (!preparing || tok !== token)
            return;
        preparing = false;
        prepTimeout.stop();
        active = true;
        swap.restart();
        finish.interval = duration * 1000 + 120 + 400;   // Startverzögerung + Puffer
        finish.restart();
    }
    Timer {
        id: prepTimeout

        interval: 1500                    // Bild lädt nicht -> trotzdem weitermachen
        onTriggered: root.ready(root.token)
    }

    // neues Bild unter dem Overlay setzen, sobald das Overlay steht
    Timer {
        id: swap

        interval: 70           // ein paar Frames, bis das Overlay das alte Bild zeigt (sonst blitzt das neue auf)
        onTriggered: Quickshell.execDetached(["awww", "img", root.newPath, "--transition-type", "simple", "--transition-step", "255"])
    }
    Timer {
        id: finish

        onTriggered: root.active = false
    }
}
