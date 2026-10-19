import QtQuick
import QtQuick.Controls
import qs.components
import qs.services

// Seitenkopf + Seitenwechsel mit Richtungs-Transitions + Pending-Leiste
Item {
    id: root

    property int dir: 1
    readonly property var category: Backend.category(Ui.current)
    readonly property Item page: stack.currentItem

    function show(name) {
        const names = Backend.categories.map(c => c.name);
        dir = names.indexOf(name) >= names.indexOf(lastName) ? 1 : -1;
        lastName = name;
        const cat = Backend.category(name);
        if (!cat)
            return;
        const comp = cat.groups.some(g => g.kind === "wallpaper") ? wallpaperComp : genericComp;
        if (stack.depth === 0)
            stack.push(comp, { catName: name }, StackView.Immediate);
        else
            stack.replace(null, comp, { catName: name });
        Qt.callLater(() => {
            if (stack.currentItem)
                stack.currentItem.forceActiveFocus();
        });
    }
    property string lastName: ""

    Binding {
        target: Ui
        property: "pendingCount"
        value: root.page?.pendingCount ?? 0
    }

    Connections {
        target: Ui
        function onNavigated(name) {
            root.show(name);
        }
    }

    // ── Kopf ──
    Item {
        id: header

        width: parent.width
        height: 84

        Rectangle {
            id: iconBlob

            x: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            height: 56
            radius: 18
            color: Theme.primary

            property int spin: 0
            rotation: spin
            Behavior on rotation { Anim { curve: "spatialSlow"; duration: 800 } }

            Icon {
                id: headIcon

                anchors.centerIn: parent
                icon: root.category?.icon ?? "settings"
                size: 30
                fill: 1
                color: Theme.primaryFg
                rotation: -iconBlob.rotation
            }
        }

        Column {
            anchors.left: iconBlob.right
            anchors.leftMargin: 18
            anchors.right: parent.right
            anchors.rightMargin: 70
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Txt {
                id: title

                text: Ui.current
                font.pixelSize: Theme.size.headline + 4
                font.weight: Font.Bold

                Behavior on text {
                    SequentialAnimation {
                        ParallelAnimation {
                            Anim { target: title; property: "opacity"; to: 0; duration: 110; curve: "standard" }
                            Anim { target: title; property: "y"; to: -10 * root.dir; duration: 110; curve: "standard" }
                        }
                        PropertyAction {}
                        PropertyAction { target: title; property: "y"; value: 14 * root.dir }
                        ScriptAction { script: iconBlob.spin += 90 * root.dir }
                        ParallelAnimation {
                            Anim { target: title; property: "opacity"; to: 1; curve: "effects"; duration: 260 }
                            Anim { target: title; property: "y"; to: 0; curve: "spatial" }
                        }
                    }
                }
            }
            Txt {
                id: subtitle

                width: parent.width
                color: Theme.surfaceFgDim
                font.pixelSize: Theme.size.small + 1
                text: {
                    const c = root.category;
                    if (!c)
                        return "";
                    const d = c.groups.map(g => g.description).find(x => x);
                    const n = c.groups.reduce((a, g) => a + g.items.length, 0);
                    if (c.immediate)
                        return Backend.t("wp_group_desc", "Bild anklicken und Akzentfarbe wählen – wird sofort angewendet.");
                    if (d)
                        return d;
                    return n > 0 ? Backend.t("qs_entries", "{n} Einträge", { n: n }) : Backend.t("pref_group_hint", "Werte anpassen und mit \"Übernehmen\" bestätigen.");
                }
            }
        }
    }

    StackView {
        id: stack

        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true

        replaceEnter: Transition {
            ParallelAnimation {
                Anim { property: "opacity"; from: 0; to: 1; curve: "effects"; duration: 320 }
                Anim { property: "y"; from: 60 * root.dir; to: 0; curve: "spatialSlow" }
                Anim { property: "scale"; from: 0.96; to: 1; curve: "spatialSlow" }
            }
        }
        replaceExit: Transition {
            ParallelAnimation {
                Anim { property: "opacity"; from: 1; to: 0; curve: "emphasizedAccel"; duration: 180 }
                Anim { property: "y"; from: 0; to: -40 * root.dir; curve: "emphasizedAccel"; duration: 220 }
                Anim { property: "scale"; from: 1; to: 0.97; curve: "emphasizedAccel"; duration: 220 }
            }
        }
    }

    Component {
        id: genericComp

        GenericPage {}
    }
    Component {
        id: wallpaperComp

        WallpaperPage {}
    }

    PendingBar {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        count: root.page?.pendingCount ?? 0
        busy: root.page?.busy ?? false
    }
}
