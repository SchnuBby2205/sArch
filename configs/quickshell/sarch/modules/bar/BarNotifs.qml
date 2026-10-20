import QtQuick
import qs.components
import qs.services

// Benachrichtigungen: Klick öffnet die Zentrale, Rechtsklick = Nicht stören, Mittelklick = Popups weg
Item {
    id: root

    property var cfg
    property bool vertical: false
    property real thick: 40
    property bool preview: false

    implicitWidth: btn.implicitWidth
    implicitHeight: btn.implicitHeight

    BarButton {
        id: btn

        cfg: root.cfg
        thick: root.thick
        vertical: root.vertical
        icon: Notifs.dnd ? "notifications_paused" : Notifs.unread > 0 ? "notifications_unread" : "notifications"
        accent: Notifs.dnd ? Theme.tertiary : Theme.primary
        active: Notifs.centerOpen || Notifs.dnd
        badge: Notifs.dnd ? 0 : Notifs.unread
        iconRotation: wiggle.r
        onClicked: if (!root.preview)
            Notifs.centerRequested()
        onRightClicked: if (!root.preview)
            Notifs.setDnd(!Notifs.dnd)
        onMiddleClicked: Notifs.clearPopups()
    }

    // Glocke wackelt bei jeder neuen Benachrichtigung
    QtObject {
        id: wiggle
        property real r: 0
    }
    SequentialAnimation {
        id: ring
        NumberAnimation { target: wiggle; property: "r"; to: 18; duration: 80 }
        NumberAnimation { target: wiggle; property: "r"; to: -14; duration: 100 }
        NumberAnimation { target: wiggle; property: "r"; to: 9; duration: 90 }
        NumberAnimation { target: wiggle; property: "r"; to: -5; duration: 90 }
        NumberAnimation { target: wiggle; property: "r"; to: 0; duration: 140; easing.type: Easing.OutBack }
    }
    property int lastUnread: Notifs.unread
    Connections {
        target: Notifs
        function onUnreadChanged() {
            if (Notifs.unread > root.lastUnread && !Notifs.dnd)
                ring.restart();
            root.lastUnread = Notifs.unread;
        }
    }
}
