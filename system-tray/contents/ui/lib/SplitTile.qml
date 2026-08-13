import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../js/colorType.js" as ColorType

ColumnLayout {
    id: tile

    property string iconSource
    property string label
    property string tooltipText: ""
    property bool active: false

    signal clicked
    signal arrowClicked
    signal rightClicked
    signal middleClicked

    // Generic reorder-gesture signals, recognized entirely within
    // toggleMA below (the same MouseArea that already owns ordinary
    // click/right-click/middle-click for the main tile body — see the
    // state-machine comment on toggleMA for why gesture ownership lives
    // here rather than in a separate handler). Consumers such as
    // QuickSettingsPager.qml connect to these without needing to know
    // anything about how the gesture is recognized. scenePos is in
    // window/scene coordinates (Item.mapToItem(null, x, y)), matching
    // what the pager's drag engine already expects.
    signal reorderDragStarted(point scenePos)
    signal reorderDragMoved(point scenePos)
    signal reorderDragFinished(bool committed)

    activeFocusOnTab: true
    focus: true

    Keys.onReturnPressed: tile.clicked()
    Keys.onSpacePressed: tile.clicked()

    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color fg: active ? (ColorType.isDark(Kirigami.Theme.backgroundColor) ? "#1E1E1E" : "#FFFFFF") : Kirigami.Theme.textColor

    spacing: 4
    Layout.fillWidth: true
    Layout.preferredWidth: 0

    Rectangle {
        id: bg
        Layout.fillWidth: true
        Layout.preferredHeight: width / 2
        radius: 4
        border.width: 1
        border.color: active ? "transparent" : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
        color: {
            if (active)
                return accent;
            if (toggleMA.containsPress)
                return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10);
            if (toggleMA.containsMouse || arrowMA.containsMouse)
                return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06);
            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04);
        }

        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: tile.tooltipText
            subText: ""
            textFormat: Text.PlainText
        }

        MouseArea {
            id: toggleMA
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.70
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            // ---- Double-click + hold + drag reorder recognizer --------
            //
            // This lives in the SAME MouseArea that already owns clicking
            // (rather than a second handler layered on top of it) because
            // that is the one thing that is guaranteed, on every Qt Quick
            // version, to already own the whole press/move/release
            // sequence with no possibility of another item stealing it —
            // there is nothing left for it to compete with.
            //
            // States (gestureState):
            //   "idle"           — no relevant press history.
            //   "awaitingSecond" — a first click just completed; a second
            //                      LEFT press landing on this same spot
            //                      within doubleClickInterval is treated
            //                      as the potential start of a reorder.
            //   "armed"          — that second press is down; watching
            //                      movement for the drag threshold.
            //   "dragging"       — threshold exceeded; a live reorder owns
            //                      this pointer sequence. The eventual
            //                      release is NOT allowed to also emit an
            //                      ordinary click (see suppressClick).
            //
            // Deliberately hardcoded constants: this project has no
            // existing reference to a live QStyleHints/native
            // double-click-interval or drag-threshold value anywhere in
            // its QML, and guessing at an unverified global here risks a
            // broken property reference (a hard runtime error) for the
            // sake of matching an OS setting by a few tens of
            // milliseconds. 400ms / 8px both match common desktop
            // defaults. See the report for this tradeoff.
            readonly property int doubleClickInterval: 400 // ms
            readonly property int doubleClickDistance: 8 // px, local coords
            readonly property int dragThreshold: 8 // px, local coords

            property string gestureState: "idle"
            property real firstClickTime: 0
            property point firstClickPos: Qt.point(0, 0)
            property point pressPos: Qt.point(0, 0)
            property bool suppressClick: false

            onPressed: function (mouse) {
                if (mouse.button !== Qt.LeftButton) {
                    // A right/middle press never participates in the
                    // reorder gesture, and also invalidates any pending
                    // "awaiting second click" window so a stray
                    // right-click in between two left-clicks can't later
                    // be mistaken for their second press.
                    toggleMA.gestureState = "idle";
                    return;
                }
                if (toggleMA.gestureState === "awaitingSecond") {
                    const dt = Date.now() - toggleMA.firstClickTime;
                    const dx = mouse.x - toggleMA.firstClickPos.x;
                    const dy = mouse.y - toggleMA.firstClickPos.y;
                    toggleMA.gestureState = (dt <= toggleMA.doubleClickInterval && Math.abs(dx) <= toggleMA.doubleClickDistance && Math.abs(dy) <= toggleMA.doubleClickDistance) ? "armed" : "idle";
                } else {
                    // Fresh press with no pending window — covers "idle",
                    // and also defensively covers "armed"/"dragging",
                    // self-healing a gesture that never reached a clean
                    // onReleased/onCanceled (e.g. the popup was torn down
                    // mid-drag) rather than leaving this tile stuck.
                    toggleMA.gestureState = "idle";
                }
                toggleMA.pressPos = Qt.point(mouse.x, mouse.y);
            }

            onPositionChanged: function (mouse) {
                if (!toggleMA.pressed) {
                    // hoverEnabled means this can fire on pure hover too;
                    // only ever act on it while a button is actually held.
                    return;
                }
                if (toggleMA.gestureState === "armed") {
                    const dx = mouse.x - toggleMA.pressPos.x;
                    const dy = mouse.y - toggleMA.pressPos.y;
                    if (Math.hypot(dx, dy) > toggleMA.dragThreshold) {
                        toggleMA.gestureState = "dragging";
                        tile.reorderDragStarted(toggleMA.mapToItem(null, mouse.x, mouse.y));
                    }
                } else if (toggleMA.gestureState === "dragging") {
                    tile.reorderDragMoved(toggleMA.mapToItem(null, mouse.x, mouse.y));
                }
            }

            onReleased: function (mouse) {
                if (mouse.button !== Qt.LeftButton) {
                    return;
                }
                if (toggleMA.gestureState === "dragging") {
                    tile.reorderDragFinished(true);
                    toggleMA.gestureState = "idle";
                    // The upcoming onClicked for this same release must
                    // NOT also fire the tile's ordinary action — the
                    // gesture already resolved as a completed reorder.
                    toggleMA.suppressClick = true;
                } else {
                    // A plain first click, or a double-click release that
                    // never crossed the drag threshold — let onClicked
                    // below handle it completely normally (this is what
                    // keeps ordinary clicks instant: nothing here delays
                    // or second-guesses that action), and open the
                    // window for a possible second press.
                    toggleMA.firstClickTime = Date.now();
                    toggleMA.firstClickPos = Qt.point(mouse.x, mouse.y);
                    toggleMA.gestureState = "awaitingSecond";
                }
            }

            onCanceled: {
                if (toggleMA.gestureState === "dragging") {
                    tile.reorderDragFinished(false);
                }
                toggleMA.gestureState = "idle";
            }

            onClicked: function (mouse) {
                if (toggleMA.suppressClick) {
                    toggleMA.suppressClick = false;
                    return;
                }
                if (mouse.button === Qt.RightButton) {
                    tile.rightClicked();
                } else if (mouse.button === Qt.MiddleButton) {
                    tile.middleClicked();
                } else {
                    tile.clicked();
                }
            }
        }

        MouseArea {
            id: arrowMA
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.30
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.arrowClicked()
        }

        Kirigami.Icon {
            x: parent.width * 0.35 - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Kirigami.Units.iconSizes.smallMedium
            height: Kirigami.Units.iconSizes.smallMedium
            source: tile.iconSource
            color: tile.fg
            isMask: true
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * 0.70
            width: 1
            height: parent.height * 0.5
            color: active ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        }

        Kirigami.Icon {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: Kirigami.Units.iconSizes.small
            height: Kirigami.Units.iconSizes.small
            source: "go-next"
            color: tile.fg
            isMask: true
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        text: tile.label
        color: Kirigami.Theme.textColor
        font.pixelSize: 10
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
    }
}
