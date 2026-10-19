import QtQuick
import qs.components
import qs.services

// Schriften für Oberfläche (Dunst + Rofi) und Terminal (kitty)
Item {
    id: root

    required property var page
    property var fontData: null
    property bool loading: true

    width: parent?.width ?? 400
    height: loading ? 200 : grid.implicitHeight

    function load() {
        loading = true;
        Backend.call(["fonts"], res => {
            loading = false;
            if (res.ok)
                fontData = res;
        });
    }
    function sync() {
        const ch = {};
        if (ui.modified)
            ch.ui = { family: ui.family, size: ui.size };
        if (term.modified)
            ch.term = { family: term.family, size: term.size };
        page.setPending("fonts", Object.keys(ch).length ? { fonts: ch } : null);
    }

    Component.onCompleted: load()

    Connections {
        target: root.page
        function onResetTokenChanged() {
            ui.family = ui.originalFamily;
            ui.size = ui.originalSize;
            term.family = term.originalFamily;
            term.size = term.originalSize;
        }
    }

    Spinner {
        anchors.centerIn: parent
        visible: root.loading
        width: 40
        height: 40
    }

    Grid {
        id: grid

        width: parent.width
        columns: width > 900 ? 2 : 1
        columnSpacing: 14
        rowSpacing: 14
        visible: !root.loading && root.fontData !== null

        FontCard {
            id: ui

            order: 0
            width: (grid.width - (grid.columns - 1) * 14) / grid.columns
            title: Backend.t("font_ui_group", "Oberfläche (Dunst + Rofi)")
            subtitle: Backend.t("font_ui_desc", "Schrift für Benachrichtigungen und Menüs")
            icon: "notifications"
            families: root.fontData?.families ?? []
            originalFamily: root.fontData?.ui.family ?? ""
            originalSize: root.fontData?.ui.size ?? 12
            family: originalFamily
            size: originalSize
            minSize: 4
            maxSize: 72
            onEdited: root.sync()
        }
        FontCard {
            id: term

            order: 1
            width: (grid.width - (grid.columns - 1) * 14) / grid.columns
            title: Backend.t("font_term_group", "Terminal (kitty)")
            subtitle: Backend.t("font_term_desc", "Nur Monospace-Schriften")
            icon: "terminal"
            families: root.fontData?.mono ?? []
            originalFamily: root.fontData?.term.family ?? ""
            originalSize: root.fontData?.term.size ?? 10
            family: originalFamily
            size: originalSize
            minSize: 4
            maxSize: 48
            step: 0.5
            onEdited: root.sync()
        }
    }
}
