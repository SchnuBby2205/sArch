pragma Singleton

import QtQuick
import Quickshell

// Uhr für die Bar (sekundengenau, Timer läuft synchron zur vollen Sekunde)
Singleton {
    id: root

    property date now: new Date()

    Timer {
        running: true
        repeat: true
        interval: 1000 - (new Date().getMilliseconds())
        triggeredOnStart: true
        onTriggered: {
            root.now = new Date();
            interval = 1000 - root.now.getMilliseconds() + 5;
        }
    }
}
