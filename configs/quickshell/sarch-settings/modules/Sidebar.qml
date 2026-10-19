import QtQuick
import qs.components
import qs.services

Item {
    id: root

    signal closeRequested

    property alias searchField: search

    readonly property var filtered: {
        const q = Ui.search.trim().toLowerCase();
        const out = [];
        for (const c of Backend.categories) {
            const n = q === "" ? 0 : matchCount(c, q);
            if (q === "" || n > 0 || c.name.toLowerCase().includes(q))
                out.push({ cat: c, matches: n });
        }
        return out;
    }

    function matchCount(c, q) {
        let n = 0;
        for (const g of c.groups)
            for (const it of g.items) {
                const hay = [it.label, it.title, it.name, it.value, it.description, (it.keys || []).join(" ")].join(" ").toLowerCase();
                if (hay.includes(q))
                    n++;
            }
        return n;
    }

    // Beim Suchen automatisch zur ersten Kategorie mit Treffern springen
    onFilteredChanged: {
        if (Ui.search.trim() === "" || Ui.pendingCount > 0 || filtered.length === 0)
            return;
        const cur = filtered.find(f => f.cat.name === Ui.current);
        if (!cur || cur.matches === 0) {
            const hit = filtered.find(f => f.matches > 0) || filtered[0];
            Qt.callLater(() => Ui.navigate(hit.cat.name));
        }
    }

    function indexOfCurrent() {
        for (let i = 0; i < filtered.length; i++)
            if (filtered[i].cat.name === Ui.current)
                return i;
        return -1;
    }

    // ── Kopf ──
    Row {
        id: head

        x: 20
        y: 22
        spacing: 14

        Rectangle {
            id: logo

            width: 48
            height: 48
            radius: logoArea.containsMouse ? 24 : 16
            color: Theme.primaryContainer
            rotation: logoArea.containsMouse ? 90 : 0
            Behavior on radius { Anim { curve: "spatial" } }
            Behavior on rotation { Anim { curve: "spatialSlow" } }

            Icon {
                anchors.centerIn: parent
                icon: "settings"
                size: 28
                fill: 1
                color: Theme.primaryContainerFg
                rotation: -parent.rotation
            }
            MouseArea {
                id: logoArea

                anchors.fill: parent
                hoverEnabled: true
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Txt {
                text: Backend.t("app_title", "Einstellungen")
                font.pixelSize: Theme.size.title + 2
                font.weight: Font.Bold
            }
            Txt {
                text: "sArch · Hyprland"
                font.pixelSize: Theme.size.small
                color: Theme.surfaceFgDim
            }
        }
    }

    Field {
        id: search

        x: 16
        y: head.y + head.height + 20
        width: root.width - 32
        compact: true
        icon: "search"
        placeholder: Backend.t("qs_search", "Suchen …  (Strg+F)")
        onEdited: Ui.search = text
        Connections {
            target: Ui
            function onSearchChanged() {
                if (search.text !== Ui.search)
                    search.text = Ui.search;
            }
        }

        IconButton {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            size: 30
            icon: "close"
            visible: Ui.search !== ""
            onClicked: Ui.search = ""
        }
    }

    // ── Kategorien ──
    ListView {
        id: list

        readonly property int rowH: 40
        readonly property int idx: root.indexOfCurrent()
        onIdxChanged: if (idx >= 0)
            positionViewAtIndex(idx, ListView.Contain)

        x: 12
        y: search.y + search.height + 14
        width: root.width - 24
        height: footer.y - y - 12
        clip: true
        spacing: 2
        model: root.filtered
        boundsBehavior: Flickable.StopAtBounds

        add: Transition {
            Anim { property: "opacity"; from: 0; to: 1; curve: "effects" }
            Anim { property: "x"; from: -20; curve: "spatial" }
        }
        displaced: Transition {
            Anim { property: "y"; curve: "spatial" }
        }

        // elastischer Auswahl-Indikator
        Rectangle {
            id: indicator

            property real targetY: list.idx * (list.rowH + list.spacing)
            property real edgeTop: 0
            property real edgeBot: 0
            property bool ready: false

            z: -1
            x: 0
            y: edgeTop
            width: list.width
            height: edgeBot - edgeTop
            radius: height / 2
            color: Theme.secondaryContainer
            visible: list.idx >= 0

            Behavior on edgeTop { enabled: indicator.ready; Anim { id: topAnim; curve: "spatial" } }
            Behavior on edgeBot { enabled: indicator.ready; Anim { id: botAnim; curve: "spatial" } }
            onTargetYChanged: {
                const down = targetY > edgeTop;
                topAnim.duration = down ? 560 : 340;
                botAnim.duration = down ? 340 : 560;
                edgeTop = targetY;
                edgeBot = targetY + list.rowH;
            }
            Component.onCompleted: {
                edgeTop = targetY;
                edgeBot = targetY + list.rowH;
                ready = true;
            }
        }

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property bool selected: modelData.cat.name === Ui.current

            width: list.width
            height: list.rowH

            Icon {
                id: ico

                x: 16
                anchors.verticalCenter: parent.verticalCenter
                icon: row.modelData.cat.icon
                size: 22
                fill: row.selected ? 1 : 0
                color: row.selected ? Theme.secondaryContainerFg : Theme.surfaceFgDim
                scale: row.selected ? 1.1 : 1
                Behavior on scale { Anim { curve: "spatialFast" } }
            }
            Txt {
                x: 52
                width: parent.width - 52 - badge.width - 16
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.cat.name
                font.pixelSize: Theme.size.label - 1
                font.weight: row.selected ? Font.DemiBold : Font.Normal
                color: row.selected ? Theme.secondaryContainerFg : Theme.surfaceFg
            }
            Rectangle {
                id: badge

                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: row.modelData.matches > 0
                width: Math.max(24, cnt.implicitWidth + 12)
                height: 22
                radius: 11
                color: Theme.primary

                Txt {
                    id: cnt

                    anchors.centerIn: parent
                    text: row.modelData.matches
                    font.pixelSize: Theme.size.tiny
                    font.weight: Font.Bold
                    color: Theme.primaryFg
                }
            }
            StateLayer {
                radius: height / 2
                hoverOpacity: row.selected ? 0 : 0.06
                onClicked: Ui.navigate(row.modelData.cat.name)
            }
        }
    }

    // ── aktuelles Wallpaper ──
    Item {
        id: footer

        x: 16
        width: root.width - 32
        height: 96
        y: root.height - height - 16

        readonly property string wpPage: Backend.resolvePage("wallpaper")

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.large
            color: Theme.surfaceHigh
        }

        RoundedImage {
            id: wpImg

            anchors.fill: parent
            radius: Theme.radius.large
            source: Theme.wallpaper !== "" ? "file://" + Theme.wallpaper : ""
            sourceSize.width: 520
            scale: footArea.containsMouse ? 1.04 : 1
            Behavior on scale { Anim { curve: "spatialSlow" } }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.large
            gradient: Gradient {
                GradientStop { position: 0.3; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.75) }
            }
        }

        Row {
            x: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            spacing: -6

            Repeater {
                model: [Theme.primary, Theme.secondary, Theme.tertiary]

                Rectangle {
                    required property color modelData
                    required property int index

                    width: 22
                    height: 22
                    radius: 11
                    color: modelData
                    border.width: 2
                    border.color: Qt.rgba(0, 0, 0, 0.35)
                    z: 3 - index
                }
            }
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 13
            width: parent.width - 100
            horizontalAlignment: Text.AlignRight
            text: Theme.wallpaper.split("/").pop().replace(/\.[^.]+$/, "")
            color: "white"
            font.pixelSize: Theme.size.small
            font.weight: Font.Medium
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: 34
            height: 34
            radius: 17
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: footArea.containsMouse ? 1 : 0
            scale: footArea.containsMouse ? 1 : 0.6
            Behavior on opacity { Anim { curve: "effects" } }
            Behavior on scale { Anim { curve: "spatialFast" } }

            Icon {
                anchors.centerIn: parent
                icon: "palette"
                size: 18
                fill: 1
                color: "white"
            }
        }

        MouseArea {
            id: footArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Ui.navigate(footer.wpPage)
        }
    }
}
