pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper-Übergang (awww): ~/.config/sArch/wallpaper-transition.conf, gelesen von bin/sarch_wallpaper_set.sh
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string path: `${home}/.config/sArch/wallpaper-transition.conf`
    readonly property string setter: `${home}/.config/sArch/bin/sarch_wallpaper_set.sh`

    property string type: "random"
    property real duration: 1.6
    property string bezier: ".54,0,.34,.99"
    property bool cursor: true

    // Effekte (Reihenfolge = Anzeige)
    readonly property var types: [
        { id: "random", icon: "shuffle", label: "Zufällig", desc: "Jedes Mal ein anderer Effekt" },
        { id: "grow", icon: "radio_button_checked", label: "Kreis", desc: "Öffnet sich als Kreis – am Mauszeiger" },
        { id: "outer", icon: "filter_tilt_shift", label: "Von außen", desc: "Kreis schließt sich zum Mauszeiger hin" },
        { id: "wave", icon: "waves", label: "Welle", desc: "Wellenkante in zufälligem Winkel" },
        { id: "wipe", icon: "swipe_right", label: "Wischen", desc: "Gerade Kante in zufälligem Winkel" },
        { id: "slide", icon: "open_in_full", label: "Schieben", desc: "Von einem zufälligen Rand" },
        { id: "slice", icon: "content_cut", label: "Zerschneiden", desc: "Schräge Streifen fliegen nach rechts oben und links unten weg" },
        { id: "flip", icon: "grid_view", label: "Kacheln", desc: "Kacheln klappen in einer Welle um" },
        { id: "center", icon: "center_focus_strong", label: "Mitte", desc: "Kreis aus der Bildschirmmitte" },
        { id: "any", icon: "scatter_plot", label: "Irgendwo", desc: "Kreis an einer zufälligen Stelle" },
        { id: "fade", icon: "gradient", label: "Überblenden", desc: "Weiches Ineinanderblenden" },
        { id: "simple", icon: "crop_square", label: "Einfach", desc: "Schlichtes Umschalten" }
    ]
    readonly property var curves: [
        { id: ".54,0,.34,.99", label: "Weich" },
        { id: ".05,.9,.1,1", label: "Schnell" },
        { id: ".34,1.4,.64,1", label: "Federnd" },
        { id: "0,0,1,1", label: "Linear" }
    ]

    function save() {
        file.setText(`TYPE=${type}\nDURATION=${duration.toFixed(1)}\nBEZIER=${bezier}\nCURSOR=${cursor}\nFPS=auto\n`);
    }
    function set(key, value) {
        root[key] = value;
        saveTimer.restart();
    }
    // aktuelles Wallpaper mit dem eingestellten Übergang neu setzen
    // Vorschau: erst auf eine abgedunkelte Version des Bildes, dann zurück – beide Male mit dem Effekt
    // (awww zeigt beim Setzen desselben Bildes keinen Übergang)
    function tryNow() {
        saveTimer.stop();
        save();
        tryTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: root.save()
    }
    Timer {
        id: tryTimer

        interval: 150      // Datei erst schreiben lassen
        onTriggered: Quickshell.execDetached([root.setter, "--try"])
    }

    FileView {
        id: file

        path: root.path
        printErrors: false
        onLoaded: {
            for (const line of text().split("\n")) {
                const i = line.indexOf("=");
                if (i < 0)
                    continue;
                const k = line.slice(0, i).trim(), v = line.slice(i + 1).trim();
                if (k === "TYPE" && v)
                    root.type = v;
                else if (k === "DURATION" && !isNaN(Number(v)))
                    root.duration = Number(v);
                else if (k === "BEZIER" && v)
                    root.bezier = v;
                else if (k === "CURSOR")
                    root.cursor = v !== "false";
            }
        }
    }
}
