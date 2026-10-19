import QtQuick
import qs.components
import qs.services

// Variable (NAME = wert) oder Autostart-Befehl als einzeilige Karte
Card {
    id: root

    required property var item
    required property var page

    readonly property bool isVar: item.kind === "variable"
    readonly property string original: item.value
    property string value: item.value
    readonly property bool modified: value !== original

    width: parent?.width ?? 400
    height: 72
    highlighted: modified

    Connections {
        target: root.page
        function onResetTokenChanged() {
            root.value = root.original;
            field.text = root.original;
        }
    }

    Rectangle {
        id: lead

        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: root.isVar ? Math.max(150, Math.min(240, nameTxt.implicitWidth + 28)) : 44
        height: 44
        radius: 14
        color: root.isVar ? Theme.primaryContainer : Theme.secondaryContainer

        Txt {
            id: nameTxt

            visible: root.isVar
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 16)
            text: root.item.name ?? ""
            mono: true
            font.weight: Font.Bold
            color: Theme.primaryContainerFg
        }
        Icon {
            visible: !root.isVar
            anchors.centerIn: parent
            icon: "terminal"
            size: 22
            color: Theme.secondaryContainerFg
        }
    }

    Txt {
        id: eq

        visible: root.isVar
        anchors.left: lead.right
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "="
        mono: true
        font.pixelSize: Theme.size.title
        color: Theme.surfaceFgDim
    }

    Field {
        id: field

        anchors.left: root.isVar ? eq.right : lead.right
        anchors.leftMargin: 12
        anchors.right: del.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        compact: true
        mono: true
        text: root.item.value
        modified: root.modified
        onEdited: {
            root.value = text;
            root.page.setPending(root.item.uid, root.modified ? { uid: root.item.uid, value: text } : null);
        }
    }

    IconButton {
        id: del

        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        icon: "delete"
        variant: "danger"
        size: 38
        opacity: root.hovered ? 1 : 0.35
        Behavior on opacity { Anim { curve: "effects" } }
        tooltip: Backend.t("tooltip_delete", "Eintrag löschen")
        onClicked: Ui.confirm({
            title: Backend.t("delete_heading", "Wirklich löschen?"),
            body: root.isVar ? Backend.t("qs_delete_var", "Variable \"{name}\" wird entfernt.", { name: root.item.name })
                             : Backend.t("delete_body_autostart", "Dieser Autostart-Eintrag wird entfernt."),
            ok: Backend.t("btn_delete", "Löschen"),
            danger: true,
            icon: "delete"
        }, () => root.page.deleteItem(root.item.uid))
    }
}
