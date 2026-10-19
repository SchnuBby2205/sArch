import QtQuick
import QtQuick.Controls
import qs.components
import qs.services
import qs.modules.items

// Seite für alle INI-gesteuerten Kategorien (Slider, Auswahl, Records, Variablen, Autostart, Schriften)
Item {
    id: pg

    required property string catName
    readonly property var category: Backend.category(catName)

    property bool animateIn: true
    property var pending: ({})
    property int resetToken: 0
    property bool busy: false
    readonly property int pendingCount: Object.keys(pending).length
    property real savedY: -1

    function setPending(uid, change) {
        const p = Object.assign({}, pending);
        if (change)
            p[uid] = change;
        else
            delete p[uid];
        pending = p;
    }

    function reset() {
        pending = {};
        resetToken += 1;
    }

    function matches(it) {
        const q = Ui.search.trim().toLowerCase();
        if (q === "")
            return true;
        const hay = [it.label, it.title, it.name, it.value, it.description, (it.keys || []).join(" ")].join(" ").toLowerCase();
        return hay.includes(q);
    }

    function refresh(toEnd) {
        savedY = flick.contentY;
        animateIn = false;
        Backend.reload(() => {
            pending = {};
            Qt.callLater(() => {
                const maxY = Math.max(0, flick.contentHeight - flick.height);
                flick.contentY = toEnd ? maxY : Math.min(savedY, maxY);
            });
        });
    }

    function apply() {
        if (busy || pendingCount === 0)
            return;
        busy = true;
        const changes = [];
        let fonts = null;
        for (const k in pending) {
            if (pending[k].fonts)
                fonts = pending[k].fonts;
            else
                changes.push(pending[k]);
        }
        const errors = [];
        const finish = () => {
            busy = false;
            if (errors.length) {
                Ui.error(Backend.t("error_heading", "Fehler beim Schreiben"), errors);
            } else {
                Ui.toast(Backend.t("toast_applied", "\"{category}\" erfolgreich übernommen.", { category: pg.catName }), "task_alt");
            }
            refresh();
        };
        const doFonts = () => {
            if (!fonts)
                return finish();
            Backend.call(["apply-fonts", Backend.json(fonts)], res => {
                if (!res.ok)
                    errors.push(...(res.errors || [res.error]));
                finish();
            });
        };
        if (changes.length === 0)
            return doFonts();
        Backend.call(["apply", Backend.json({ changes: changes })], res => {
            if (!res.ok)
                errors.push(...(res.errors || [res.error]));
            doFonts();
        });
    }

    function deleteItem(uid) {
        Backend.call(["delete", Backend.json({ uid: uid })], res => {
            if (res.ok) {
                Ui.toast(Backend.t("toast_entry_deleted", "Eintrag gelöscht."), "delete");
                refresh();
            } else {
                Ui.error(Backend.t("error_heading", "Fehler beim Schreiben"), res.errors || [res.error]);
            }
        });
    }

    function create(add, title) {
        let fields;
        let icon = "add";
        if (add.kind === "variable") {
            fields = [
                { key: "name", label: Backend.t("name_label", "Name"), type: "text", mono: true, value: "" },
                { key: "value", label: Backend.t("value_label", "Wert"), type: "text", mono: true, value: "" }
            ];
            icon = "data_object";
        } else if (add.kind === "command") {
            fields = [{ key: "value", label: Backend.t("new_autostart_value_ph", "\"waybar\""), type: "text", mono: true, value: "" }];
            icon = "rocket_launch";
        } else {
            fields = add.fields.map(f => Object.assign({}, f, { value: f.options && f.options.length ? f.options[0] : "" }));
            icon = pg.category?.icon ?? "add";
        }
        const heading = add.kind === "variable" ? Backend.t("new_variable_heading", "Neue Variable")
                      : add.kind === "command" ? Backend.t("new_autostart_heading", "Neuer Autostart-Eintrag")
                      : Backend.t("new_entry_heading", "Neuen Eintrag anlegen");
        const body = add.kind === "variable" ? Backend.t("new_variable_body", "Name und Wert eingeben.")
                   : add.kind === "command" ? Backend.t("new_autostart_body", "Befehl eingeben (z.B. \"waybar\" oder waybar)")
                   : Backend.t("new_entry_body", "Felder ausfüllen und bestätigen.");
        Ui.form({ title: heading, body: body, icon: icon, fields: fields, ok: Backend.t("btn_create", "Anlegen") }, values => {
            const payload = { kind: add.kind, section: add.section };
            if (add.kind === "variable") {
                payload.name = values.name;
                payload.value = values.value;
            } else if (add.kind === "command") {
                payload.value = values.value;
            } else {
                payload.values = values;
            }
            Backend.call(["create", Backend.json(payload)], res => {
                if (res.ok) {
                    Ui.toast(Backend.t("toast_entry_created", "Eintrag angelegt."), "add_circle");
                    refresh(true);
                } else {
                    Ui.error(Backend.t("error_heading", "Fehler beim Schreiben"), res.errors || [res.error]);
                }
            });
        });
    }

    // Shortcut-Anbindung (Strg+S / Pending-Leiste)
    Connections {
        target: Ui
        function onRequestApply() {
            pg.apply();
        }
        function onRequestReset() {
            pg.reset();
        }
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentHeight: col.height + 120
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2500
        maximumFlickVelocity: 4500

        ScrollBar.vertical: ScrollBar {
            id: sb

            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: Theme.alpha(Theme.surfaceFgDim, sb.pressed ? 0.6 : sb.hovered ? 0.45 : 0.25)
            }
            background: null
        }

        Column {
            id: col

            width: flick.width - 28
            x: 4
            spacing: 26

            Repeater {
                model: pg.category ? pg.category.groups : []

                Column {
                    id: grp

                    required property var modelData
                    required property int index

                    readonly property int visibleCount: {
                        let n = 0;
                        for (const it of modelData.items)
                            if (pg.matches(it))
                                n++;
                        return n;
                    }
                    readonly property bool special: modelData.kind === "fonts"
                    readonly property bool single: pg.category.groups.length === 1
                    readonly property bool showHeader: (!single || modelData.add || (modelData.description ?? "") !== "") && !special

                    width: col.width
                    spacing: 10
                    visible: special ? Ui.search === "" : (visibleCount > 0 || (Ui.search === "" && modelData.add))

                    // Gruppenkopf
                    Item {
                        width: parent.width
                        height: visible ? Math.max(44, headCol.implicitHeight) : 0
                        visible: grp.showHeader

                        Column {
                            id: headCol

                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.right: addBtn.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Row {
                                spacing: 10

                                Txt {
                                    visible: !grp.single
                                    text: grp.modelData.title
                                    font.pixelSize: Theme.size.title
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: cntTxt.implicitWidth + 14
                                    height: 22
                                    radius: 11
                                    color: Theme.alpha(Theme.primary, 0.14)
                                    visible: grp.modelData.items.length > 0

                                    Txt {
                                        id: cntTxt

                                        anchors.centerIn: parent
                                        text: (Ui.search !== "" ? `${grp.visibleCount} / ${grp.modelData.items.length}` : grp.modelData.items.length)
                                              + (grp.single ? "  " + Backend.t("qs_entries_label", "Einträge") : "")
                                        font.pixelSize: Theme.size.tiny
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }
                                }
                            }
                            Txt {
                                width: parent.width
                                text: grp.modelData.description ?? ""
                                visible: text !== "" && !grp.single
                                font.pixelSize: Theme.size.small
                                color: Theme.surfaceFgDim
                            }
                        }

                        Btn {
                            id: addBtn

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!grp.modelData.add
                            variant: "tonal"
                            icon: "add"
                            text: Backend.t("qs_new", "Neu")
                            onClicked: pg.create(grp.modelData.add, grp.modelData.title)
                        }
                    }

                    // Einträge
                    Column {
                        width: parent.width
                        spacing: grp.modelData.kind === "records" || grp.modelData.kind === "variable" || grp.modelData.kind === "autostart" ? 8 : 12

                        Repeater {
                            model: grp.modelData.items

                            Loader {
                                id: ld

                                required property var modelData
                                required property int index

                                width: parent.width
                                visible: pg.matches(modelData)
                                sourceComponent: modelData.kind === "slider" ? sliderC
                                               : modelData.kind === "dropdown" ? choiceC
                                               : modelData.kind === "record" ? recordC
                                               : lineC

                                Component {
                                    id: sliderC

                                    SliderItem {
                                        item: ld.modelData
                                        page: pg
                                        order: ld.index + grp.index * 2
                                        animateIn: pg.animateIn
                                    }
                                }
                                Component {
                                    id: choiceC

                                    ChoiceItem {
                                        item: ld.modelData
                                        page: pg
                                        order: ld.index + grp.index * 2
                                        animateIn: pg.animateIn
                                    }
                                }
                                Component {
                                    id: recordC

                                    RecordItem {
                                        item: ld.modelData
                                        page: pg
                                        icon: pg.category?.icon ?? "tune"
                                        order: ld.index
                                        animateIn: pg.animateIn
                                    }
                                }
                                Component {
                                    id: lineC

                                    LineItem {
                                        item: ld.modelData
                                        page: pg
                                        order: ld.index
                                        animateIn: pg.animateIn
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        active: grp.special
                        visible: active
                        width: parent.width
                        sourceComponent: FontsGroup {
                            page: pg
                        }
                    }
                }
            }
        }
    }

    // Nichts gefunden
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: Ui.search !== "" && col.height < 20
        opacity: visible ? 1 : 0
        Behavior on opacity { Anim { curve: "effects" } }

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            icon: "search_off"
            size: 64
            color: Theme.alpha(Theme.surfaceFgDim, 0.5)
        }
        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Backend.t("qs_no_results", "Nichts gefunden für „{q}“", { q: Ui.search })
            color: Theme.surfaceFgDim
        }
    }
}
