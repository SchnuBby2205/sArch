import QtQuick
import qs.components
import qs.services

// Aufklappbare Karte für Keybinds, Window-/Layer-/Workspace-Rules, Animationen …
Card {
    id: root

    required property var item
    required property var page
    property string icon: "tune"
    property bool expanded: false

    readonly property var originals: {
        const o = {};
        for (const f of item.fields)
            o[f.key] = f.value;
        return o;
    }
    property var values: Object.assign({}, originals)
    readonly property bool modified: {
        for (const k in originals)
            if (String(values[k] ?? "") !== String(originals[k] ?? ""))
                return true;
        return false;
    }
    readonly property bool isBind: values.use_mainmod !== undefined
    readonly property string mainModName: item.keys.length && originals.use_mainmod === "yes" ? item.keys[0] : "SUPER"
    readonly property var keys: {
        if (!isBind)
            return [];
        const k = [];
        if (values.use_mainmod === "yes")
            k.push(mainModName);
        if (values.modifier && values.modifier !== "none")
            k.push(values.modifier);
        if (values.key)
            k.push(values.key);
        return k;
    }
    readonly property string title: (isBind ? values.description : (values.name || values.leaf || values.workspace)) || item.title
    readonly property string summary: {
        if (isBind) {
            const cmd = (values.command || "").replace(/^hl\.dsp\./, "");
            return cmd + (values.argument ? `(${values.argument})` : "()");
        }
        const parts = [];
        for (const f of item.fields) {
            const v = values[f.key];
            if (v && v !== "" && v !== root.title)
                parts.push(`${f.label}: ${v}`);
        }
        return parts.join("  ·  ");
    }

    width: parent?.width ?? 400
    height: header.height + body.height
    clip: true
    highlighted: modified || expanded

    Behavior on height {
        Anim { curve: root.expanded ? "spatial" : "emphasized" }
    }

    function setField(k, v) {
        const nv = Object.assign({}, values);
        nv[k] = v;
        values = nv;
        page.setPending(item.uid, modified ? { uid: item.uid, fields: values } : null);
    }

    Connections {
        target: root.page
        function onResetTokenChanged() {
            root.values = Object.assign({}, root.originals);
        }
    }

    Item {
        id: header

        width: parent.width
        height: 76

        StateLayer {
            radius: Theme.radius.large
            hoverOpacity: 0.04
            onClicked: root.expanded = !root.expanded
        }

        Rectangle {
            id: bubble

            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: root.expanded ? 22 : 14
            color: root.expanded ? Theme.primary : Theme.secondaryContainer
            Behavior on radius { Anim { curve: "spatial" } }
            Behavior on color { CAnim {} }

            Icon {
                anchors.centerIn: parent
                icon: root.icon
                size: 22
                fill: root.expanded ? 1 : 0
                color: root.expanded ? Theme.primaryFg : Theme.secondaryContainerFg
            }
        }

        Column {
            x: 74
            width: parent.width - 74 - tools.width - 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Row {
                width: parent.width
                spacing: 8

                Txt {
                    width: Math.min(implicitWidth, parent.width - 20)
                    text: Backend.tr(root.title)
                    font.pixelSize: Theme.size.label
                    font.weight: Font.Medium
                }
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.tertiary
                    anchors.verticalCenter: parent.verticalCenter
                    scale: root.modified ? 1 : 0
                    Behavior on scale { Anim { curve: "spatialFast" } }
                }
            }

            Row {
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.keys

                    Row {
                        required property string modelData
                        required property int index

                        spacing: 6

                        Txt {
                            visible: index > 0
                            text: "+"
                            color: Theme.surfaceFgDim
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Keycap {
                            label: modelData
                            accent: index === 0 && modelData === root.mainModName && root.values.use_mainmod === "yes"
                        }
                    }
                }
                Txt {
                    width: parent.width - (root.keys.length ? x : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: root.keys.length ? 8 : 0
                    text: root.summary
                    mono: root.isBind
                    font.pixelSize: Theme.size.small
                    color: Theme.surfaceFgDim
                }
            }
        }

        Row {
            id: tools

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            IconButton {
                icon: "undo"
                size: 36
                visible: root.modified
                tooltip: Backend.t("btn_reset", "Zurücksetzen")
                onClicked: {
                    root.values = Object.assign({}, root.originals);
                    root.page.setPending(root.item.uid, null);
                }
            }
            IconButton {
                icon: "delete"
                variant: "danger"
                size: 36
                visible: root.item.deletable
                opacity: root.hovered || root.expanded ? 1 : 0
                Behavior on opacity { Anim { curve: "effects" } }
                tooltip: Backend.t("tooltip_delete", "Eintrag löschen")
                onClicked: Ui.confirm({
                    title: Backend.t("delete_heading", "Wirklich löschen?"),
                    body: Backend.t("delete_body", "\"{title}\" wird dauerhaft aus der Datei entfernt.", { title: Backend.tr(root.title) }),
                    ok: Backend.t("btn_delete", "Löschen"),
                    danger: true,
                    icon: "delete"
                }, () => root.page.deleteItem(root.item.uid))
            }
            IconButton {
                icon: "expand_more"
                size: 36
                rotation: root.expanded ? 180 : 0
                Behavior on rotation { Anim { curve: "spatial" } }
                onClicked: root.expanded = !root.expanded
            }
        }
    }

    Item {
        id: body

        y: header.height
        width: parent.width
        height: root.expanded ? grid.implicitHeight + 22 : 0
        opacity: root.expanded ? 1 : 0
        Behavior on opacity { Anim { curve: "effects"; duration: root.expanded ? 350 : 120 } }

        Rectangle {
            x: 20
            width: parent.width - 40
            height: 1
            color: Theme.alpha(Theme.outline, 0.15)
        }

        Grid {
            id: grid

            x: 20
            y: 16
            width: parent.width - 40
            columns: width > 560 ? 2 : 1
            columnSpacing: 12
            rowSpacing: 10

            Repeater {
                model: root.expanded || body.height > 0 ? root.item.fields : []

                FieldEditor {
                    required property var modelData

                    width: (grid.width - (grid.columns - 1) * grid.columnSpacing) / grid.columns
                    def: Object.assign({}, modelData, {
                        label: modelData.block ? `${modelData.label}  ·  ${modelData.block}` : modelData.label
                    })
                    original: root.originals[modelData.key] ?? ""
                    value: root.values[modelData.key] ?? ""
                    mono: ["argument", "class", "title", "command", "bezier"].indexOf(modelData.key) >= 0
                    onChanged: v => root.setField(modelData.key, v)
                }
            }
        }
    }
}
