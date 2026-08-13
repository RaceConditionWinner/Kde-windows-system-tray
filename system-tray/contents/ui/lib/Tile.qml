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
    signal rightClicked
    signal middleClicked

    // See SplitTile.qml's toggleMA for the full state-machine comment —
    // this mirrors the same recognizer for tiles with no separate arrow
    // region, where the whole tile is the "main body".
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
            if (ma.containsPress)
                return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10);
            if (ma.containsMouse)
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
            id: ma
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            // Double-click + hold + drag reorder recognizer — identical
            // state machine to SplitTile.qml's toggleMA; see the comment
            // there for the full rationale (single pointer owner, why the
            // constants are hardcoded, why ordinary clicks stay instant).
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
                    ma.gestureState = "idle";
                    return;
                }
                if (ma.gestureState === "awaitingSecond") {
                    const dt = Date.now() - ma.firstClickTime;
                    const dx = mouse.x - ma.firstClickPos.x;
                    const dy = mouse.y - ma.firstClickPos.y;
                    ma.gestureState = (dt <= ma.doubleClickInterval && Math.abs(dx) <= ma.doubleClickDistance && Math.abs(dy) <= ma.doubleClickDistance) ? "armed" : "idle";
                } else {
                    ma.gestureState = "idle";
                }
                ma.pressPos = Qt.point(mouse.x, mouse.y);
            }

            onPositionChanged: function (mouse) {
                if (!ma.pressed) {
                    return;
                }
                if (ma.gestureState === "armed") {
                    const dx = mouse.x - ma.pressPos.x;
                    const dy = mouse.y - ma.pressPos.y;
                    if (Math.hypot(dx, dy) > ma.dragThreshold) {
                        ma.gestureState = "dragging";
                        tile.reorderDragStarted(ma.mapToItem(null, mouse.x, mouse.y));
                    }
                } else if (ma.gestureState === "dragging") {
                    tile.reorderDragMoved(ma.mapToItem(null, mouse.x, mouse.y));
                }
            }

            onReleased: function (mouse) {
                if (mouse.button !== Qt.LeftButton) {
                    return;
                }
                if (ma.gestureState === "dragging") {
                    tile.reorderDragFinished(true);
                    ma.gestureState = "idle";
                    ma.suppressClick = true;
                } else {
                    ma.firstClickTime = Date.now();
                    ma.firstClickPos = Qt.point(mouse.x, mouse.y);
                    ma.gestureState = "awaitingSecond";
                }
            }

            onCanceled: {
                if (ma.gestureState === "dragging") {
                    tile.reorderDragFinished(false);
                }
                ma.gestureState = "idle";
            }

            onClicked: function (mouse) {
                if (ma.suppressClick) {
                    ma.suppressClick = false;
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

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.smallMedium
            height: Kirigami.Units.iconSizes.smallMedium
            source: tile.iconSource
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
