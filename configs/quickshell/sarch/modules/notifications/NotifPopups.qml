import QtQuick
import qs.components
import qs.services

// Stapel der aktuellen Popups (neueste oben). Liegt in einem eigenen Fenster am Bildschirmrand.
Item {
    id: root

    readonly property real cardWidth: 400
    property string position: "top-right"
    readonly property bool fromBottom: position.startsWith("bottom")
    readonly property string side: position.endsWith("left") ? "left" : position.endsWith("right") ? "right" : "center"
    implicitWidth: cardWidth + 24
    implicitHeight: Math.max(1, list.contentHeight + 24)

    ListView {
        id: list

        x: 12
        y: 12
        width: root.cardWidth
        height: contentHeight
        interactive: false
        spacing: 10
        // unten: neueste Meldung direkt am Rand, der Stapel wächst nach oben
        verticalLayoutDirection: root.fromBottom ? ListView.BottomToTop : ListView.TopToBottom
        model: Notifs.popupModel

        add: Transition {
            ParallelAnimation {
                Anim { property: "x"; from: root.side === "left" ? -root.cardWidth * 0.6 : root.side === "right" ? root.cardWidth * 0.6 : 0; to: 0; curve: "spatialSlow" }
                Anim { property: "opacity"; from: 0; to: 1; curve: "effects"; duration: 260 }
                Anim { property: "scale"; from: 0.92; to: 1; curve: "spatial" }
            }
        }
        remove: Transition {
            ParallelAnimation {
                Anim { property: "opacity"; to: 0; curve: "effects"; duration: 180 }
                Anim { property: "scale"; to: 0.9; curve: "emphasizedAccel"; duration: 220 }
            }
        }
        displaced: Transition {
            Anim { property: "y"; curve: "spatial" }
        }

        delegate: NotifCard {
            id: card

            required property int nid
            readonly property var n: Notifs.obj(nid)

            width: root.cardWidth
            app: n?.appName ?? ""
            appIcon: n?.appIcon ?? ""
            summary: n?.summary ?? ""
            body: n?.body ?? ""
            image: n?.image ?? ""
            urgency: Number(n?.urgency ?? 1)
            progress: n ? Notifs.progress(n) : -1
            actions: n?.actions ?? []
            time: Date.now()
            timeout: n ? Notifs.timeoutMs(n) : 5000

            onDismissed: Notifs.dismissPopup(nid)
            onExpired: Notifs.expirePopup(nid)
            onActivated: Notifs.activate(nid)
            onActionInvoked: id => Notifs.invoke(nid, id)

            // ersetzte Benachrichtigung (gleiche ID, z. B. Lautstärke): Ablauf neu starten
            Connections {
                target: card.n
                ignoreUnknownSignals: true
                function onSummaryChanged() { card.restartTimer(); }
                function onBodyChanged() { card.restartTimer(); }
                function onHintsChanged() { card.restartTimer(); }
            }
        }
    }
}
