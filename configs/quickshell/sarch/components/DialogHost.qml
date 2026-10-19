import QtQuick
import qs.services

// Modale Dialoge: Bestätigen, Formular, Fehlerliste
Item {
    id: root

    property bool isOpen: false
    property string mode: "confirm"           // confirm | form | error
    property var opts: ({})
    property var callback: null
    property var values: ({})

    function openConfirm(o, cb) {
        mode = "confirm";
        opts = o;
        callback = cb;
        isOpen = true;
        card.forceActiveFocus();
    }
    function openForm(o, cb) {
        mode = "form";
        opts = o;
        const v = {};
        for (const f of (o.fields || []))
            v[f.key] = f.value !== undefined ? String(f.value) : (f.options && f.options.length ? f.options[0] : "");
        values = v;
        callback = cb;
        isOpen = true;
        Qt.callLater(() => {
            if (formRepeater.count > 0 && formRepeater.itemAt(0).item?.forceFocus)
                formRepeater.itemAt(0).item.forceFocus();
            else
                card.forceActiveFocus();
        });
    }
    function openError(title, lines) {
        mode = "error";
        opts = {
            title: title,
            icon: "error",
            lines: lines,
            ok: Backend.t("btn_ok", "OK")
        };
        callback = null;
        isOpen = true;
        card.forceActiveFocus();
    }
    function close() {
        isOpen = false;
    }
    function accept() {
        const cb = callback;
        const vals = Object.assign({}, values);
        isOpen = false;
        if (cb)
            cb(mode === "form" ? vals : true);
    }

    visible: scrim.opacity > 0
    z: 900

    Rectangle {
        id: scrim

        anchors.fill: parent
        radius: Theme.radius.xl
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: root.isOpen ? 1 : 0
        Behavior on opacity { Anim { curve: "effects"; duration: 260 } }

        MouseArea {
            anchors.fill: parent
            enabled: root.isOpen
            onClicked: root.close()
        }
    }

    Rectangle {
        id: card

        readonly property bool danger: !!root.opts.danger || root.mode === "error"

        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.isOpen ? 0 : 40
        width: Math.min(root.width - 80, root.mode === "form" ? 600 : 460)
        height: content.implicitHeight + 48
        radius: Theme.radius.xl
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.alpha(Theme.outline, 0.2)
        opacity: root.isOpen ? 1 : 0
        scale: root.isOpen ? 1 : 0.88
        focus: root.isOpen

        Behavior on anchors.verticalCenterOffset { Anim { curve: root.isOpen ? "spatial" : "emphasizedAccel" } }
        Behavior on opacity { Anim { curve: "effects"; duration: 220 } }
        Behavior on scale { Anim { curve: root.isOpen ? "spatial" : "emphasizedAccel" } }
        Behavior on height { Anim { curve: "spatial" } }

        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: root.accept()
        Keys.onEnterPressed: root.accept()

        MouseArea {
            anchors.fill: parent
        } // Klicks nicht zum Scrim durchreichen

        Column {
            id: content

            x: 24
            y: 24
            width: parent.width - 48
            spacing: 16

            Rectangle {
                width: 56
                height: 56
                radius: 18
                anchors.horizontalCenter: parent.horizontalCenter
                color: card.danger ? Theme.errorContainer : Theme.secondaryContainer
                rotation: root.isOpen ? 0 : -30
                Behavior on rotation { Anim { curve: "spatialSlow" } }

                Icon {
                    anchors.centerIn: parent
                    icon: root.opts.icon || (root.mode === "form" ? "add" : "help")
                    size: 28
                    fill: 1
                    color: card.danger ? Theme.errorContainerFg : Theme.secondaryContainerFg
                }
            }

            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.opts.title || ""
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                font.pixelSize: Theme.size.headline - 4
                font.weight: Font.DemiBold
            }

            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
                text: root.opts.body || ""
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: Theme.surfaceFgDim
            }

            // Fehlerliste
            Column {
                width: parent.width
                spacing: 6
                visible: root.mode === "error"

                Repeater {
                    model: root.mode === "error" ? (root.opts.lines || []) : []

                    Rectangle {
                        required property string modelData

                        width: parent.width
                        height: errTxt.implicitHeight + 16
                        radius: Theme.radius.small
                        color: Theme.alpha(Theme.error, 0.1)

                        Txt {
                            id: errTxt

                            x: 12
                            width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            mono: true
                            font.pixelSize: Theme.size.small
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideNone
                            color: Theme.error
                        }
                    }
                }
            }

            // Formular
            Grid {
                id: formGrid

                width: parent.width
                visible: root.mode === "form"
                columns: (root.opts.fields || []).length > 3 ? 2 : 1
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    id: formRepeater

                    model: root.mode === "form" && root.isOpen ? (root.opts.fields || []) : []

                    Loader {
                        id: fl

                        required property var modelData
                        required property int index

                        width: (formGrid.width - (formGrid.columns - 1) * 12) / formGrid.columns
                        sourceComponent: FieldEditor {
                            def: fl.modelData
                            value: root.values[fl.modelData.key] ?? ""
                            original: ""
                            showModified: false
                            mono: !!fl.modelData.mono || ["argument", "class", "title", "bezier"].indexOf(fl.modelData.key) >= 0
                            onChanged: v => {
                                const nv = Object.assign({}, root.values);
                                nv[fl.modelData.key] = v;
                                root.values = nv;
                            }
                            onSubmitted: root.accept()
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8
                topPadding: 4

                Btn {
                    visible: root.mode !== "error"
                    variant: "text"
                    text: root.opts.cancel || Backend.t("btn_cancel", "Abbrechen")
                    onClicked: root.close()
                }
                Btn {
                    variant: card.danger && root.mode !== "error" ? "danger" : "filled"
                    icon: root.mode === "form" ? "add" : card.danger && root.mode !== "error" ? "delete" : "check"
                    text: root.opts.ok || Backend.t("btn_ok", "OK")
                    onClicked: root.accept()
                }
            }
        }
    }
}
