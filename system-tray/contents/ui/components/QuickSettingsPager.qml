/*
    QuickSettingsPager — Windows 11–style paged, drag-reorderable Quick
    Settings grid for the Action Panel.

    Replaces the old flat 3x3 GridLayout of nine tiles with a surface that
    shows at most 3 columns x 2 rows (6 tiles) at a time, paging to
    additional 6-tile pages via mouse wheel / touchpad, with a Windows-11
    style page-dot indicator, and lets the user press-and-hold a tile to
    pick it up and drop it anywhere in the ordered collection (including
    across pages). The custom order is persisted via
    Plasmoid.configuration.quickSettingsOrder.

    ARCHITECTURE NOTES (see the accompanying report for the full writeup):

    - Tile identity vs. tile position are deliberately decoupled. The
      Repeater's model is `defaultOrder` — a fixed, never-reassigned list
      of the nine canonical tile ids — so all nine tile components
      (Network/Bluetooth/etc., each with real backend connections such as
      NetworkManager or BluezQt) are created exactly once and never
      destroyed/recreated for the lifetime of the popup, regardless of
      paging, reordering, or visibility-config changes. Only each
      delegate's on-screen *position* changes, via ordinary x/y bindings.
      This matters: recreating these components on every drag tick would
      repeatedly tear down and reopen live DBus/NetworkManager/Bluetooth
      connections.

    - "canonicalOrder" is the persisted, committed order (all nine ids).
      "liveOrder" is what all position math actually reads; it mirrors
      canonicalOrder outside of a drag, and becomes a live, provisional
      permutation of it while a drag is in progress. Configuration is
      written exactly once, on a successful drop — never on intermediate
      pointer movement.

    - Visibility is computed per id via tileVisible(), which intentionally
      mirrors the exact per-tile `visible:` expressions the old
      ActionPanel.qml GridLayout used to set at each tile's instantiation
      site (e.g. BatterySaverToggle's own internal `visible: available`
      binding was already being overridden there by
      `visible: Plasmoid.configuration.showBatterySaver` — an outer
      instantiation-site property binding always wins over a type's own
      internal default binding in QML). Reproducing that here, id by id,
      keeps tile visibility byte-for-byte identical to before.

    - Geometry is centralized in targetPos()/slotIndexFromViewportPos(),
      an exact forward/inverse pair expressed in viewport-local pixels
      (already netted against the current page), so no other place in
      this file does ad hoc pixel math.

    - Drag activation and tracking are NOT implemented here at all. An
      earlier version of this file used an ancestor TapHandler with
      longPressThreshold to detect a press-and-hold over each tile's own
      SplitTile/Tile MouseAreas; that relied on Qt Quick's passive-grab
      phase letting the handler observe the press alongside the
      MouseArea, and it did not work on real Plasma runtime testing — the
      MouseArea evidently keeps sole ownership of the sequence in
      practice, so the ancestor handler never got a usable chance to
      recognize the hold. The gesture (now double-click + hold + drag) is
      recognized inside SplitTile.qml/Tile.qml's own main-body MouseArea
      instead — the one thing guaranteed to already own the whole
      press/move/release sequence with nothing else to compete with — and
      exposed generically as reorderDragStarted/reorderDragMoved/
      reorderDragFinished(committed) signals. This file's only job is to
      forward those three signals into beginDrag()/updateDrag()/endDrag()
      below via one Connections block per delegate (see the Repeater
      delegate further down); the reorder *engine* (canonicalOrder,
      liveOrder, targetPos(), edge paging, persistence, etc.) is
      unchanged from before. Individual tile components (NetworkToggle
      and friends) need no changes at all, since they inherit these
      signals from their SplitTile/Tile root.
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "." as Components

Item {
    id: pager

    signal requestPage(string name)

    // Scale multiplier passed down from ActionPanel (kept distinct from
    // Item's own built-in `scale` transform property, deliberately not
    // reused here).
    property real uiScale: 1

    Layout.fillWidth: true
    implicitWidth: 0
    implicitHeight: pager.contentPageHeight
    visible: pager.visibleOrder.length > 0

    // ---- Sizing / spacing --------------------------------------------
    // Mirrors the spacing the old 3x3 GridLayout used (rowSpacing: 12*scale,
    // columnSpacing: 6*scale).
    readonly property real columnSpacing: 6 * pager.uiScale
    readonly property real rowSpacing: 12 * pager.uiScale
    readonly property real indicatorDotSize: 6 * pager.uiScale

    readonly property real tileWidth: pager.width > 0 ? (pager.width - 2 * pager.columnSpacing) / 3 : 0

    // Uniform per-tile height, measured from the always-visible Network
    // tile (defaultOrder[0]) once it has loaded. Every tile shares the
    // same Tile.qml/SplitTile.qml structure at a given width, so any
    // always-loaded tile is a valid reference.
    readonly property real tileHeight: {
        const refItem = tileRepeater.count > 0 ? tileRepeater.itemAt(0) : null
        const li = refItem ? refItem.loaderItem : null
        return (li && li.implicitHeight > 0) ? li.implicitHeight : (pager.tileWidth / 2 + 18)
    }

    readonly property real rowPitch: pager.tileHeight + pager.rowSpacing
    readonly property real pagePitch: pager.rowPitch * 2
    readonly property real contentPageHeight: pager.tileHeight * 2 + pager.rowSpacing

    // ---- Canonical tile identifiers -----------------------------------
    readonly property var defaultOrder: ["network", "bluetooth", "airplane", "batterySaver", "nightLight", "colorScheme", "dnd", "micMute", "hotspot"]

    // Mirrors the exact visible: expression each tile was instantiated
    // with in the old ActionPanel.qml GridLayout. See the architecture
    // note at the top of this file for why this must match exactly
    // (some of these intentionally override a tile's own internal
    // availability check, exactly as before).
    function tileVisible(id) {
        switch (id) {
        case "network":
            return true
        case "bluetooth":
            return true
        case "airplane":
            return Plasmoid.configuration.showAirplane
        case "batterySaver":
            return Plasmoid.configuration.showBatterySaver
        case "nightLight":
            return Plasmoid.configuration.showNightLight
        case "colorScheme":
            return Plasmoid.configuration.showColorScheme
        case "dnd":
            return Plasmoid.configuration.showDnd
        case "micMute":
            return Plasmoid.configuration.showMicMute
        case "hotspot":
            return Plasmoid.configuration.showHotspot
        default:
            return false
        }
    }

    function arraysEqual(a, b) {
        if (!a || !b || a.length !== b.length)
            return false
        for (let i = 0; i < a.length; i++) {
            if (a[i] !== b[i])
                return false
        }
        return true
    }

    // Defensive normalization (see report, "Configuration" section):
    // drops unknown/duplicate ids, keeps valid saved ids in their saved
    // relative order, then appends any known id missing from the saved
    // list. Falls back to the full default order if nothing usable is
    // saved yet.
    function normalizeOrder(saved) {
        const seen = {}
        const result = []
        if (saved) {
            for (let i = 0; i < saved.length; i++) {
                const id = saved[i]
                if (pager.defaultOrder.indexOf(id) !== -1 && !seen[id]) {
                    seen[id] = true
                    result.push(id)
                }
            }
        }
        for (let j = 0; j < pager.defaultOrder.length; j++) {
            const id = pager.defaultOrder[j]
            if (!seen[id]) {
                seen[id] = true
                result.push(id)
            }
        }
        return result
    }

    // Persisted, committed order (all nine ids, visible or not). Only
    // recomputed when the underlying configuration value changes — i.e.
    // on load, and after this file's own commit on a successful drop.
    property var canonicalOrder: pager.normalizeOrder(Plasmoid.configuration.quickSettingsOrder)

    // Working copy all position math reads. Mirrors canonicalOrder
    // whenever no drag is in progress; becomes a live, provisional
    // permutation of it during a drag so the surrounding tiles can
    // reflow immediately without writing configuration on every pointer
    // movement (see beginDrag/updateDrag/endDrag below).
    property var liveOrder: pager.canonicalOrder

    onCanonicalOrderChanged: {
        if (!pager.draggingId) {
            pager.liveOrder = pager.canonicalOrder
        }
    }

    readonly property var visibleOrder: pager.liveOrder.filter(pager.tileVisible)

    readonly property int pageCount: pager.visibleOrder.length === 0 ? 0 : Math.ceil(pager.visibleOrder.length / 6)
    readonly property bool showIndicator: pager.pageCount > 1

    property int currentPage: 0
    property bool pageTransitioning: false

    onVisibleOrderChanged: {
        const maxPage = Math.max(0, pager.pageCount - 1)
        if (pager.currentPage > maxPage) {
            pager.currentPage = maxPage
        }
    }

    onCurrentPageChanged: {
        pager.pageTransitioning = true
        transitionLockTimer.restart()
    }

    Timer {
        id: transitionLockTimer
        interval: 190
        repeat: false
        onTriggered: pager.pageTransitioning = false
    }

    function goToPage(p) {
        const clamped = Math.max(0, Math.min(pager.pageCount - 1, p))
        if (clamped === pager.currentPage)
            return false
        pager.currentPage = clamped
        return true
    }

    // ---- Centralized geometry (forward + inverse pair) -----------------
    // Both viewport-local: y=0 is the top of the currently visible page.
    function targetPos(visIndex) {
        const row = Math.floor(visIndex / 3)
        const col = visIndex % 3
        const page = Math.floor(row / 2)
        const rowInPage = row % 2
        const x = col * (pager.tileWidth + pager.columnSpacing)
        const y = page * pager.pagePitch + rowInPage * pager.rowPitch - pager.currentPage * pager.pagePitch
        return Qt.point(x, y)
    }

    function slotIndexFromViewportPos(cx, cy) {
        const total = pager.visibleOrder.length
        if (total <= 0)
            return 0
        let col = Math.floor(cx / (pager.tileWidth + pager.columnSpacing))
        col = Math.max(0, Math.min(2, col))
        const globalY = cy + pager.currentPage * pager.pagePitch
        let page = Math.floor(globalY / pager.pagePitch)
        page = Math.max(0, page)
        let withinPage = globalY - page * pager.pagePitch
        let rowInPage = Math.floor(withinPage / pager.rowPitch)
        rowInPage = Math.max(0, Math.min(1, rowInPage))
        const row = page * 2 + rowInPage
        const idx = row * 3 + col
        return Math.max(0, Math.min(total - 1, idx))
    }

    // ---- Drag / reorder state ------------------------------------------
    property string draggingId: ""
    property real dragX: 0
    property real dragY: 0
    property real dragStartX: 0
    property real dragStartY: 0
    property point dragStartScenePos: Qt.point(0, 0)
    property var dragSnapshotOrder: []
    property int lastAppliedTargetIndex: -1
    property int edgeDirection: 0 // -1 = towards previous page, 1 = towards next page, 0 = none

    property real wheelAccum: 0
    onPageTransitioningChanged: {
        if (pager.pageTransitioning)
            pager.wheelAccum = 0
    }

    function beginDrag(id, slotItem, scenePos) {
        if (pager.draggingId)
            return
        pager.dragSnapshotOrder = pager.canonicalOrder.slice()
        pager.dragStartScenePos = scenePos
        pager.dragStartX = slotItem.x
        pager.dragStartY = slotItem.y
        pager.dragX = slotItem.x
        pager.dragY = slotItem.y
        pager.lastAppliedTargetIndex = pager.visibleOrder.indexOf(id)
        // Set last: flips slot.dragging (and its x/y binding source) only
        // once dragX/dragY already match the tile's current position, so
        // there is no one-frame jump when the binding switches over.
        pager.draggingId = id
        pager.updateEdgeDirection()
    }

    function updateDrag(scenePos) {
        if (!pager.draggingId)
            return
        const dx = scenePos.x - pager.dragStartScenePos.x
        const dy = scenePos.y - pager.dragStartScenePos.y
        pager.dragX = pager.dragStartX + dx
        pager.dragY = pager.dragStartY + dy

        const targetIndex = pager.slotIndexFromViewportPos(pager.dragX + pager.tileWidth / 2, pager.dragY + pager.tileHeight / 2)
        if (targetIndex !== pager.lastAppliedTargetIndex) {
            pager.lastAppliedTargetIndex = targetIndex
            pager.liveOrder = pager.reorderCanonical(pager.dragSnapshotOrder, pager.draggingId, targetIndex)
        }
        pager.updateEdgeDirection()
    }

    // Moves draggedId to newVisibleIndex within the VISIBLE subsequence of
    // `order`, while leaving every hidden id at its existing position in
    // the full list — so a hidden tile keeps its remembered canonical
    // slot and returns to it if the tile is re-enabled later.
    function reorderCanonical(order, draggedId, newVisibleIndex) {
        const visible = order.filter(pager.tileVisible)
        const oldIdx = visible.indexOf(draggedId)
        if (oldIdx === -1)
            return order
        const clamped = Math.max(0, Math.min(newVisibleIndex, visible.length - 1))
        if (clamped === oldIdx)
            return order
        const v2 = visible.slice()
        v2.splice(oldIdx, 1)
        v2.splice(clamped, 0, draggedId)
        const result = []
        let vi = 0
        for (let i = 0; i < order.length; i++) {
            if (pager.tileVisible(order[i])) {
                result.push(v2[vi])
                vi++
            } else {
                result.push(order[i])
            }
        }
        return result
    }

    function updateEdgeDirection() {
        if (!pager.draggingId) {
            pager.edgeDirection = 0
            return
        }
        const edgeZone = Math.max(16, pager.tileHeight * 0.35)
        if (pager.currentPage > 0 && pager.dragY < edgeZone) {
            pager.edgeDirection = -1
        } else if (pager.currentPage < pager.pageCount - 1 && (pager.dragY + pager.tileHeight) > (pager.contentPageHeight - edgeZone)) {
            pager.edgeDirection = 1
        } else {
            pager.edgeDirection = 0
        }
    }

    onEdgeDirectionChanged: {
        if (!pager.draggingId || pager.edgeDirection === 0) {
            edgePageTimer.stop()
        } else if (!edgePageTimer.running) {
            edgePageTimer.start()
        }
    }

    // Debounced cross-page auto-scroll while dragging: holding near an
    // edge for a full interval switches a page and continues dragging
    // the same tile; briefly crossing an edge and pulling back cancels it.
    Timer {
        id: edgePageTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!pager.draggingId || pager.edgeDirection === 0)
                return
            const moved = pager.goToPage(pager.currentPage + pager.edgeDirection)
            pager.updateEdgeDirection()
            if (moved && pager.draggingId && pager.edgeDirection !== 0) {
                edgePageTimer.restart()
            }
        }
    }

    function endDrag(commit) {
        if (!pager.draggingId)
            return
        edgePageTimer.stop()
        pager.edgeDirection = 0
        if (commit) {
            // liveOrder already holds the final, live-reordered
            // arrangement; commit it as the one and only configuration
            // write for this whole drag gesture.
            Plasmoid.configuration.quickSettingsOrder = pager.liveOrder
        } else {
            pager.liveOrder = pager.canonicalOrder
        }
        pager.draggingId = ""
        pager.lastAppliedTargetIndex = -1
    }

    function cancelDrag() {
        pager.endDrag(false)
    }

    Keys.onEscapePressed: {
        if (pager.draggingId) {
            pager.cancelDrag()
        }
    }

    // Reset to page 1 and drop any in-flight drag whenever the popup
    // closes, so it always reopens in a predictable state.
    Connections {
        target: systemTrayState
        function onExpandedChanged() {
            if (!systemTrayState.expanded) {
                if (pager.draggingId) {
                    pager.cancelDrag()
                }
                pager.currentPage = 0
            }
        }
    }

    Component.onCompleted: {
        // One-shot self-heal: if the saved configuration was missing,
        // malformed, or from an older version with fewer/different ids,
        // persist the normalized form once so future startups don't have
        // to keep re-normalizing a stale value.
        if (!pager.arraysEqual(Plasmoid.configuration.quickSettingsOrder, pager.canonicalOrder)) {
            Plasmoid.configuration.quickSettingsOrder = pager.canonicalOrder
        }
    }

    // ---- Per-tile component factories -----------------------------------
    // Each mirrors exactly what the old ActionPanel.qml GridLayout set at
    // that tile's instantiation site (visible:/onArrowClicked: bindings
    // included) — see the architecture note at the top of this file.
    Component {
        id: networkComp
        Components.NetworkToggle {
            onArrowClicked: pager.requestPage("network")
        }
    }
    Component {
        id: bluetoothComp
        Components.BluetoothToggle {
            onArrowClicked: pager.requestPage("bluetooth")
        }
    }
    Component {
        id: airplaneComp
        Components.AirplaneToggle {
            visible: Plasmoid.configuration.showAirplane
        }
    }
    Component {
        id: batterySaverComp
        Components.BatterySaverToggle {
            visible: Plasmoid.configuration.showBatterySaver
            onArrowClicked: pager.requestPage("battery")
        }
    }
    Component {
        id: nightLightComp
        Components.NightLightToggle {
            visible: Plasmoid.configuration.showNightLight
        }
    }
    Component {
        id: colorSchemeComp
        Components.ColorSchemeToggle {
            visible: Plasmoid.configuration.showColorScheme
        }
    }
    Component {
        id: dndComp
        Components.DndToggle {
            visible: Plasmoid.configuration.showDnd
        }
    }
    Component {
        id: micMuteComp
        Components.MicMuteToggle {
            visible: Plasmoid.configuration.showMicMute
        }
    }
    Component {
        id: hotspotComp
        Components.HotspotToggle {
            visible: Plasmoid.configuration.showHotspot
        }
    }

    function componentForId(id) {
        switch (id) {
        case "network":
            return networkComp
        case "bluetooth":
            return bluetoothComp
        case "airplane":
            return airplaneComp
        case "batterySaver":
            return batterySaverComp
        case "nightLight":
            return nightLightComp
        case "colorScheme":
            return colorSchemeComp
        case "dnd":
            return dndComp
        case "micMute":
            return micMuteComp
        case "hotspot":
            return hotspotComp
        default:
            return null
        }
    }

    // ---- Visual tree -----------------------------------------------------
    Item {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: pager.contentPageHeight
        clip: true

        WheelHandler {
            id: pageWheel
            target: null
            orientation: Qt.Vertical
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: pager.pageCount > 1 && !pager.draggingId
            onWheel: function (event) {
                if (pager.pageTransitioning)
                    return
                pager.wheelAccum += event.angleDelta.y
                if (pager.wheelAccum <= -60) {
                    pager.goToPage(pager.currentPage + 1)
                    pager.wheelAccum = 0
                } else if (pager.wheelAccum >= 60) {
                    pager.goToPage(pager.currentPage - 1)
                    pager.wheelAccum = 0
                }
            }
        }

        Repeater {
            id: tileRepeater
            model: pager.defaultOrder

            delegate: Item {
                id: slot

                required property string modelData
                required property int index

                readonly property string tileId: slot.modelData
                readonly property bool tVisible: pager.tileVisible(slot.tileId)
                readonly property int visIndex: slot.tVisible ? pager.visibleOrder.indexOf(slot.tileId) : -1
                readonly property bool dragging: pager.draggingId === slot.tileId
                readonly property point resolvedPos: slot.visIndex >= 0 ? pager.targetPos(slot.visIndex) : Qt.point(0, 0)
                readonly property Item loaderItem: ldr.item

                parent: viewport
                width: pager.tileWidth
                height: pager.tileHeight
                visible: slot.tVisible
                enabled: slot.tVisible
                z: slot.dragging ? 1000 : 1

                x: slot.dragging ? pager.dragX : slot.resolvedPos.x
                y: slot.dragging ? pager.dragY : slot.resolvedPos.y

                Behavior on x {
                    enabled: !slot.dragging
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: !slot.dragging
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                scale: slot.dragging ? 1.045 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                // Restrained elevation treatment for the picked-up tile —
                // a highlight-colored outline, no new dependencies.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 6
                    color: "transparent"
                    border.width: slot.dragging ? 2 : 0
                    border.color: Kirigami.Theme.highlightColor
                    opacity: slot.dragging ? 0.9 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                        }
                    }
                }

                Loader {
                    id: ldr
                    anchors.fill: parent
                    active: true
                    asynchronous: false
                    sourceComponent: pager.componentForId(slot.tileId)
                }

                // Reorder-gesture ownership lives in SplitTile.qml/Tile.qml
                // themselves (the same MouseArea that already owns
                // ordinary click/right-click/middle-click for this tile),
                // not in a separate handler layered on top of it — see the
                // architecture note at the top of this file for why. This
                // Connections block is the one place those generic signals
                // get wired into the pager's existing (unchanged) drag
                // engine; the loaded tile stays completely unaware of
                // paging/reordering beyond emitting these three signals.
                Connections {
                    target: ldr.item
                    function onReorderDragStarted(scenePos) {
                        pager.beginDrag(slot.tileId, slot, scenePos)
                    }
                    function onReorderDragMoved(scenePos) {
                        if (pager.draggingId === slot.tileId) {
                            pager.updateDrag(scenePos)
                        }
                    }
                    function onReorderDragFinished(committed) {
                        if (pager.draggingId === slot.tileId) {
                            pager.endDrag(committed)
                        }
                    }
                }
            }
        }
    }

    // ---- Page indicator ----------------------------------------------
    Column {
        id: indicatorColumn
        visible: pager.showIndicator

        anchors.right: parent.right
        anchors.rightMargin: -10 * pager.uiScale
        anchors.verticalCenter: viewport.verticalCenter
        spacing: 5 * pager.uiScale

        Repeater {
            model: pager.showIndicator ? pager.pageCount : 0

            delegate: Rectangle {
                id: dot
                required property int index
                readonly property bool current: dot.index === pager.currentPage

                width: pager.indicatorDotSize
                height: dot.current
                    ? pager.indicatorDotSize * 2.2
                    : pager.indicatorDotSize
                radius: width / 2

                color: dot.current
                    ? Kirigami.Theme.highlightColor
                    : Qt.rgba(
                        Kirigami.Theme.textColor.r,
                        Kirigami.Theme.textColor.g,
                        Kirigami.Theme.textColor.b,
                        0.25
                    )

                Behavior on height {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
            }
        }
    }
}
