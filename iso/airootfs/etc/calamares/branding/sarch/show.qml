/* sArch – Diashow während der Installation */
import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        id: advanceTimer
        interval: 7000
        running: false
        repeat: true
        onTriggered: nextSlide()
    }

    component SarchSlide: Slide {
        id: s
        property string icon: ""
        property string title: ""
        property string body: ""

        Rectangle {
            anchors.fill: parent
            color: "#16131a"
        }
        Column {
            anchors.centerIn: parent
            width: parent.width * 0.75
            spacing: 18
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "logo.png"
                width: 96; height: 96
                smooth: true
                visible: s.icon === "logo"
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: s.title
                color: "#f0d39a"
                font.pixelSize: 30
                font.bold: true
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: s.body
                color: "#e6e0e9"
                font.pixelSize: 17
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
        }
    }

    SarchSlide {
        icon: "logo"
        title: "Willkommen bei sArch"
        body: "Arch Linux mit Hyprland, Quickshell und Farben, die deinem Wallpaper folgen."
    }
    SarchSlide {
        title: "Alles schon an Bord"
        body: "Die Installation kopiert das komplette Live-System – kein Download nötig. Danach startest du direkt in deinen Desktop."
    }
    SarchSlide {
        title: "Tastenkürzel"
        body: "SUPER + A  App-Launcher\nSUPER + ALT + S  Einstellungen\nSUPER + W  Wallpaper\nSUPER + Backspace  Powermenü"
    }
    SarchSlide {
        title: "Nach dem ersten Start"
        body: "Die Ersteinrichtung bietet NVIDIA-Treiber, Zusatzprogramme (Steam, Lutris, TeamSpeak, VS Code) und Backups an. Später erneut: ~/sArch/install.sh → Install → ISO-Ersteinrichtung."
    }

    function onActivate() {
        presentation.currentSlide = 0;
        advanceTimer.running = true;
    }
    function onLeave() {
        advanceTimer.running = false;
    }
}
