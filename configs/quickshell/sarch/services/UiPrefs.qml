pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Darstellungs-Optionen der Oberfläche: ~/.config/sArch/ui.json
//   ambilight          Leuchten in den Wallpaper-Farben rund um Einstellungen, Picker, Launcher, Zentrale
//   ambilightStrength  0.1 … 1
//   ambilightSize      Ausdehnung 0.5 … 2
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("HOME") || ""}/.config/sArch/ui.json`

    property bool ambilight: true
    property real ambilightStrength: 0.7
    property real ambilightSize: 1.0

    function set(key, value) {
        root[key] = value;
        saveTimer.restart();
    }
    function save() {
        file.setText(JSON.stringify({
            ambilight: ambilight,
            ambilightStrength: Math.round(ambilightStrength * 100) / 100,
            ambilightSize: Math.round(ambilightSize * 100) / 100
        }, null, 2) + "\n");
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: root.save()
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (typeof d.ambilight === "boolean")
                    root.ambilight = d.ambilight;
                if (!isNaN(Number(d.ambilightStrength)))
                    root.ambilightStrength = Math.max(0.1, Math.min(1, Number(d.ambilightStrength)));
                if (!isNaN(Number(d.ambilightSize)))
                    root.ambilightSize = Math.max(0.5, Math.min(2, Number(d.ambilightSize)));
            } catch (e) {}
        }
    }
}
