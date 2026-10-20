pragma Singleton

import QtQuick
import Quickshell

// Eigene Wallpaper-Übergänge (die awww nicht kann): "slice" (Zerschneiden) und "flip" (Kacheln).
// Ablauf: Über dem Wallpaper liegt kurz ein Fenster mit dem ALTEN Bild, darunter setzt awww sofort
// das NEUE; dann wird das alte Bild animiert weggeräumt. Aufruf: bin/sarch_wallpaper_set.sh -> IPC.
Singleton {
    id: root

    property bool active: false
    property string oldSrc: ""
    property string newSrc: ""
    property string newPath: ""
    property string mode: "slice"
    property real duration: 1.6
    property int token: 0

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
        active = true;
        swap.restart();
        finish.interval = duration * 1000 + 300 + 350;   // Startverzögerung + Puffer
        finish.restart();
    }

    // neues Bild unter dem Overlay setzen, sobald das Overlay steht
    Timer {
        id: swap

        interval: 260          // Overlay muss das alte Bild schon zeigen, sonst blitzt das neue kurz auf
        onTriggered: Quickshell.execDetached(["awww", "img", root.newPath, "--transition-type", "simple", "--transition-step", "255"])
    }
    Timer {
        id: finish

        onTriggered: root.active = false
    }
}
