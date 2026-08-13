/*
    SPDX-FileCopyrightText: 2011 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2020 Konrad Materka <materka@gmail.com>
    SPDX-FileCopyrightText: 2026 Nathaniel Krebs <areyoufeelingitnowmrkrebs@gmail.com>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.draganddrop as DnD
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

ContainmentItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool reverseLayout: Plasmoid.configuration.reverseIconOrder

    // The Windows 11–style system cluster: Network, Volume and Battery.
    // This is the single QML source of truth for the three plugin ids —
    // SystemTrayState.isSystemClusterApplet() and PlasmoidItem.qml both
    // read it via this property. Keep in sync with the matching literal
    // list in systemtraymodel.cpp (calculateEffectiveStatus) and with the
    // locked-entry check in ConfigGeneral.qml, which live in different
    // compilation units and can't share this array directly.
    readonly property var systemClusterPluginIds: [
        "org.kde.plasma.networkmanagement",
        "org.kde.plasma.volume",
        "org.kde.plasma.battery"
    ]

    Layout.minimumWidth: vertical ? Kirigami.Units.iconSizes.small : mainLayout.implicitWidth + Kirigami.Units.smallSpacing
    Layout.minimumHeight: vertical ? mainLayout.implicitHeight + Kirigami.Units.smallSpacing : Kirigami.Units.iconSizes.small

    LayoutMirroring.enabled: !vertical && ((Application.layoutDirection === Qt.RightToLeft) !== reverseLayout)
    LayoutMirroring.childrenInherit: true

    readonly property alias systemTrayState: systemTrayState
    readonly property alias itemSize: tasksGrid.itemSize
    readonly property alias visibleLayout: tasksGrid
    readonly property alias hiddenLayout: expandedRepresentation.hiddenLayout
    readonly property bool oneRowOrColumn: tasksGrid.rowsOrColumns === 1

    readonly property alias hiddenModel: hiddenModel

    Component.onCompleted: {
        // We need all the plasmoiditems to be there for correct working of shortcuts.
        // Instantiators create the plasmoiditems: ensure this is done after
        // this containmentitem actually  exists so they can be immediately parented properly
        // set active and not the model, as this will cause an assert deep in Qt
        activeInstantiator.active = true;
        hiddenInstantiator.active = true;
        clusterInstantiator.active = true;
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            systemTrayState.expanded = !systemTrayState.expanded;
        }
    }

    // Excludes the three system-cluster plugin ids from the source model so
    // they get exactly one delegate each, rendered by the dedicated
    // systemCluster row/column below instead of by tasksGrid. Each applet
    // must have exactly one live visual delegate.
    KItemModels.KSortFilterProxyModel {
        id: nonClusterModel
        filterRoleName: "itemId"
        filterRowCallback: (sourceRow, sourceParent) => {
            let value = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole);
            return root.systemClusterPluginIds.indexOf(value) < 0;
        }
        Component.onCompleted: sourceModel = Plasmoid.systemTrayModel // avoid unnecessary binding, it causes loops
    }

    KItemModels.KSortFilterProxyModel {
        id: activeModel
        filterRoleName: "effectiveStatus"
        filterRowCallback: (sourceRow, sourceParent) => {
            let value = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole);
            return value === PlasmaCore.Types.ActiveStatus;
        }
        Component.onCompleted: sourceModel = nonClusterModel // avoid unnecessary binding, it causes loops
    }

    // One id-filter + status-filter pair per system-cluster member, kept as
    // three independent chains (rather than one combined/sorted model) so
    // that Network/Volume/Battery order is guaranteed by source order below
    // instead of relying on model/registration order. Each yields 0 rows
    // when that plasmoid can't currently render, so the systemCluster row
    // fails gracefully instead of showing a fake icon.
    KItemModels.KSortFilterProxyModel {
        id: networkIdModel
        filterRoleName: "itemId"
        filterRowCallback: (sourceRow, sourceParent) => sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole) === "org.kde.plasma.networkmanagement"
        Component.onCompleted: sourceModel = Plasmoid.systemTrayModel
    }
    KItemModels.KSortFilterProxyModel {
        id: networkClusterModel
        filterRoleName: "effectiveStatus"
        filterRowCallback: (sourceRow, sourceParent) => sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole) === PlasmaCore.Types.ActiveStatus
        Component.onCompleted: sourceModel = networkIdModel
    }

    KItemModels.KSortFilterProxyModel {
        id: volumeIdModel
        filterRoleName: "itemId"
        filterRowCallback: (sourceRow, sourceParent) => sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole) === "org.kde.plasma.volume"
        Component.onCompleted: sourceModel = Plasmoid.systemTrayModel
    }
    KItemModels.KSortFilterProxyModel {
        id: volumeClusterModel
        filterRoleName: "effectiveStatus"
        filterRowCallback: (sourceRow, sourceParent) => sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole) === PlasmaCore.Types.ActiveStatus
        Component.onCompleted: sourceModel = volumeIdModel
    }

    KItemModels.KSortFilterProxyModel {
        id: batteryIdModel
        filterRoleName: "itemId"
        filterRowCallback: (sourceRow, sourceParent) => sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole) === "org.kde.plasma.battery"
        Component.onCompleted: sourceModel = Plasmoid.systemTrayModel
    }
    KItemModels.KSortFilterProxyModel {
        id: batteryClusterModel
        filterRoleName: "effectiveStatus"
        filterRowCallback: (sourceRow, sourceParent) => sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole) === PlasmaCore.Types.ActiveStatus
        Component.onCompleted: sourceModel = batteryIdModel
    }

    // Watches all three cluster applets for expandedChanged, independent of
    // the rendering models above, so that indirect activation (e.g. a
    // global shortcut assigned directly to one of them) still reaches
    // systemTrayState.setActiveApplet — which redirects it to the Action
    // Panel — even though the three are excluded from activeModel/
    // hiddenModel and so wouldn't otherwise be observed by an Instantiator.
    KItemModels.KSortFilterProxyModel {
        id: clusterWatchModel
        filterRoleName: "itemId"
        filterRowCallback: (sourceRow, sourceParent) => {
            let value = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole);
            return root.systemClusterPluginIds.indexOf(value) >= 0;
        }
        Component.onCompleted: sourceModel = Plasmoid.systemTrayModel
    }

    KItemModels.KSortFilterProxyModel {
        id: hiddenModel
        filterRoleName: "effectiveStatus"
        filterRowCallback: (sourceRow, sourceParent) => {
            let value = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), filterRole);
            return value === PlasmaCore.Types.PassiveStatus
        }
        Component.onCompleted: sourceModel = Plasmoid.systemTrayModel // avoid unnecessary binding, it causes loops
    }

    Instantiator {
        id: hiddenInstantiator
        // It's important that those are inactive at creation time
        // to not create plasmoiditems too soon
        active: false
        model: hiddenModel
        delegate: Connections {
            required property QtObject applet
            required property int row
            target: applet
            function onExpandedChanged(expanded: bool) {
                if (expanded) {
                    systemTrayState.setActiveApplet(applet, row)
                }
            }
        }
    }

    Instantiator {
        id: activeInstantiator
        active: false
        model:activeModel
        delegate: Connections {
            required property QtObject applet
            required property int row
            target: applet
            function onExpandedChanged(expanded: bool) {
                if (expanded) {
                    systemTrayState.setActiveApplet(applet, row)
                }
            }
        }
    }

    Instantiator {
        id: clusterInstantiator
        // See clusterWatchModel above: this exists purely to observe
        // expandedChanged on the three system-cluster applets, which are
        // excluded from activeModel/hiddenModel and so aren't covered by
        // the two Instantiators above.
        active: false
        model: clusterWatchModel
        delegate: Connections {
            required property QtObject applet
            required property int row
            target: applet
            function onExpandedChanged(expanded: bool) {
                if (expanded) {
                    systemTrayState.setActiveApplet(applet, row)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent

        onWheel: wheel => {
            // Don't propagate unhandled wheel events
            wheel.accepted = true;
        }

        SystemTrayState {
            id: systemTrayState
        }

        CurrentItemHighLight {
            location: Plasmoid.location
            parent: root
        }

        DnD.DropArea {
            anchors.fill: parent

            preventStealing: true

            /** Extracts the name of the system tray applet in the drag data if present
            * otherwise returns null*/
            function systemTrayAppletName(event) {
                if (event.mimeData.formats.indexOf("text/x-plasmoidservicename") < 0) {
                    return null;
                }
                const plasmoidId = event.mimeData.getDataAsByteArray("text/x-plasmoidservicename");

                if (!Plasmoid.isSystemTrayApplet(plasmoidId)) {
                    return null;
                }
                return plasmoidId;
            }

            onDragEnter: event => {
                if (!systemTrayAppletName(event)) {
                    event.ignore();
                }
            }

            onDrop: event => {
                const plasmoidId = systemTrayAppletName(event);
                if (!plasmoidId) {
                    event.ignore();
                    return;
                }

                if (Plasmoid.configuration.extraItems.indexOf(plasmoidId) < 0) {
                    const extraItems = Plasmoid.configuration.extraItems;
                    extraItems.push(plasmoidId);
                    Plasmoid.configuration.extraItems = extraItems;
                }
            }
        }


        //Main Layout
        GridLayout {
            id: mainLayout

            rowSpacing: 0
            columnSpacing: 0
            anchors.fill: parent

            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

            GridView {
                id: tasksGrid

                // Explicitly define grid coordinates to prevent overlapping.
                // Three slots now share this GridLayout: ordinary items,
                // the ExpanderArrow, and the system cluster — always in
                // that order, with the ExpanderArrow fixed in the middle
                // slot. Reversing only swaps which end tasksGrid vs the
                // cluster sit on; the expander never moves. In horizontal
                // orientation this ordering is instead handled by
                // LayoutMirroring (see root.LayoutMirroring above), so both
                // tasksGrid and systemCluster keep fixed columns 0 and 2.
                Layout.row: root.vertical ? (root.reverseLayout ? 2 : 0) : 0
                Layout.column: 0

                Layout.alignment: Qt.AlignCenter

                interactive: false //disable features we don't need
                flow: root.vertical ? GridView.LeftToRight : GridView.TopToBottom

                // Tell the grid to populate bottom-to-top when flipped on a vertical panel
                verticalLayoutDirection: (root.vertical && root.reverseLayout) ? GridView.BottomToTop : GridView.TopToBottom

                // The icon size to display when not using the auto-scaling setting
                readonly property int smallIconSize: 34

                readonly property bool autoSize: Plasmoid.configuration.scaleIconsToFit

                readonly property int gridThickness: root.vertical ? root.width : root.height
                // Should change to 2 rows/columns on a 56px panel (in standard DPI)
                readonly property int rowsOrColumns: autoSize ? 1 : Math.max(1, Math.min(count, Math.floor(gridThickness / (smallIconSize + Kirigami.Units.smallSpacing))))

                // Add margins only if the panel is larger than a small icon (to avoid large gaps between tiny icons)
                readonly property int cellSpacing: Kirigami.Units.smallSpacing * Plasmoid.configuration.iconSpacing
                readonly property int smallSizeCellLength: gridThickness < smallIconSize ? smallIconSize : smallIconSize + cellSpacing

                cellHeight: {
                    if (root.vertical) {
                        return autoSize ? itemSize + (gridThickness < itemSize ? 0 : cellSpacing) : smallSizeCellLength
                    } else {
                        return autoSize ? root.height : Math.floor(root.height / rowsOrColumns)
                    }
                }
                cellWidth: {
                    if (root.vertical) {
                        return autoSize ? root.width : Math.floor(root.width / rowsOrColumns)
                    } else {
                        return autoSize ? itemSize + (gridThickness < itemSize ? 0 : cellSpacing) : smallSizeCellLength
                    }
                }

                //depending on the form factor, we are calculating only one dimension, second is always the same as root/parent
                implicitHeight: root.vertical ? cellHeight * Math.ceil(count / rowsOrColumns) : root.height
                implicitWidth: !root.vertical ? cellWidth * Math.ceil(count / rowsOrColumns) : root.width

                readonly property int itemSize: {
                    if (autoSize) {
                        return Kirigami.Units.iconSizes.roundedIconSize(Math.min(Math.min(root.width, root.height) / rowsOrColumns, Kirigami.Units.iconSizes.enormous))
                    } else {
                        return smallIconSize
                    }
                }

                model: activeModel

                delegate: ItemLoader {
                    id: delegate

                    width: tasksGrid.cellWidth
                    height: tasksGrid.cellHeight

                    // We need to recalculate the stacking order of the z values due to how keyboard navigation works
                    // the tab order depends exclusively from this, so we redo it as the position in the list
                    // ensuring tab navigation focuses the expected items
                    Component.onCompleted: {
                        let item = tasksGrid.itemAtIndex(index - 1);
                        if (item) {
                            Plasmoid.stackItemBefore(delegate, item)
                        } else {
                            item = tasksGrid.itemAtIndex(index + 1);
                        }
                        if (item) {
                            Plasmoid.stackItemAfter(delegate, item)
                        }
                    }
                }
            }

            ExpanderArrow {
                id: expander

                // Always the middle slot: with three GridLayout cells the
                // expander no longer needs to move when reverseLayout
                // flips, only tasksGrid and systemCluster trade places
                // around it.
                Layout.row: root.vertical ? 1 : 0
                Layout.column: root.vertical ? 0 : 1

                Layout.fillWidth: vertical
                Layout.fillHeight: !vertical
                Layout.alignment: vertical ? Qt.AlignVCenter : Qt.AlignHCenter
                iconSize: tasksGrid.itemSize
                visible: root.hiddenLayout.itemCount > 0
            }

            // The Windows 11–style system cluster: Network, Volume and
            // Battery, always contiguous and immediately beside the
            // ExpanderArrow, in that fixed order. A lightweight Grid
            // positioner (not a GridView) is enough since there are at
            // most 3 items and no virtualization/wrapping is needed; each
            // Repeater below contributes 0 or 1 delegate depending on
            // whether that plasmoid can currently render (see the
            // <id>ClusterModel definitions above).
            //
            // systemClusterContainer wraps the Grid so a single decorative
            // hover/active background (systemClusterHighlight) can sit
            // behind all three delegates and extend a few pixels past the
            // Grid's own bounds, without changing the Grid's layout
            // footprint. The container takes over the GridLayout cell the
            // Grid used to occupy directly, mirroring the Grid's own
            // implicit size exactly, so nothing about the existing
            // panel/expander layout changes.
            Item {
                id: systemClusterContainer

                Layout.row: root.vertical ? (root.reverseLayout ? 0 : 2) : 0
                Layout.column: root.vertical ? 0 : 2
                Layout.alignment: Qt.AlignCenter

                implicitWidth: systemCluster.implicitWidth
                implicitHeight: systemCluster.implicitHeight

                // Purely observational: tracks pointer hover over the whole
                // cluster for the highlight below. A HoverHandler never
                // grabs the pointer, so it can't intercept or compete with
                // the delegates' existing MouseArea-based click handling
                // (see PlasmoidItem.qml) — it only ever reads hover state.
                HoverHandler {
                    id: systemClusterHover
                }

                // One continuous rounded surface behind the whole cluster,
                // Windows 11 taskbar style: invisible normally, a subtle
                // highlight on hover, and a slightly stronger highlight
                // that persists while the Action Panel is open. Declared
                // before (so painted behind) the Grid below — plain sibling
                // paint order rather than z, per the existing per-delegate
                // z: x + 1 in ItemLoader.qml, so it can never end up drawn
                // on top of an icon. It also has no input handlers of its
                // own, so it can never intercept a click either.
                //
                // actionPanelShowing (not systemTrayState.expanded) is used
                // deliberately: expanded also covers Hidden Items and
                // native/themed applet popups, neither of which should
                // hold this highlight — only the Action Panel that this
                // cluster itself opens should.
                Rectangle {
                    id: systemClusterHighlight

                    readonly property real horizontalPadding: Kirigami.Units.smallSpacing
                    readonly property real verticalPadding: Math.round(Kirigami.Units.smallSpacing / 2)

                    anchors.centerIn: parent
                    width: parent.width + horizontalPadding * 2
                    height: parent.height + verticalPadding * 2

                    radius: 5
                    color: Kirigami.Theme.textColor

                    opacity: {
                        if (systemTrayState.actionPanelShowing) {
                            return 0.12
                        } else if (systemClusterHover.hovered) {
                            return 0.08
                        } else {
                            return 0
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Kirigami.Units.shortDuration
                        }
                    }
                }

                Grid {
                    id: systemCluster

                    anchors.fill: parent

                    // Force a single row (horizontal) or single column
                    // (vertical) rather than wrapping.
                    rows: root.vertical ? -1 : 1
                    columns: root.vertical ? 1 : -1
                    flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
                    spacing: 0

                    Repeater {
                        model: networkClusterModel
                        delegate: ItemLoader {
                            width: tasksGrid.cellWidth
                            height: tasksGrid.cellHeight
                        }
                    }
                    Repeater {
                        model: volumeClusterModel
                        delegate: ItemLoader {
                            width: tasksGrid.cellWidth
                            height: tasksGrid.cellHeight
                        }
                    }
                    Repeater {
                        model: batteryClusterModel
                        delegate: ItemLoader {
                            width: tasksGrid.cellWidth
                            height: tasksGrid.cellHeight
                        }
                    }
                }
            }
        }

        Timer {
            id: expandedSync
            interval: 100
            onTriggered: systemTrayState.expanded = dialog.visible;
        }

        //Main popup
        PlasmaCore.AppletPopup {
            id: dialog
            objectName: "popupWindow"
            visualParent: root
            popupDirection: switch (Plasmoid.location) {
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge
                default:
                    return Qt.TopEdge
            }
            margin: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersFloatingApplets) ? Kirigami.Units.largeSpacing : 0

            Behavior on margin {
                NumberAnimation {
                    // Since the panel animation won't be perfectly in sync,
                    // using a duration larger than the panel animation results
                    // in a better-looking animation.
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
            }

            floating: Plasmoid.location == PlasmaCore.Desktop

            removeBorderStrategy: Plasmoid.location === PlasmaCore.Types.Floating
                ? PlasmaCore.AppletPopup.AtScreenEdges
                : PlasmaCore.AppletPopup.AtScreenEdges | PlasmaCore.AppletPopup.AtPanelEdges


            hideOnWindowDeactivate: !Plasmoid.configuration.pin
            visible: systemTrayState.expanded
            appletInterface: root

            backgroundHints: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersOpaqueBackground) ? PlasmaCore.AppletPopup.SolidBackground : PlasmaCore.AppletPopup.StandardBackground

            onVisibleChanged: {
                if (!visible) {
                    expandedSync.restart();
                } else {
                    dialog.requestActivate();
                    if (expandedRepresentation.plasmoidContainer.visible) {
                        expandedRepresentation.plasmoidContainer.forceActiveFocus();
                    } else if (expandedRepresentation.hiddenLayout.visible) {
                        expandedRepresentation.hiddenLayout.forceActiveFocus();
                    }
                }
            }
            mainItem: ExpandedRepresentation {
                id: expandedRepresentation

                Keys.onEscapePressed: event => {
                    systemTrayState.expanded = false
                }

                // Being there forces the items to fully load, and they will be reparented in the stack one by one, this item is *never* visible
                // it's important this item is parented to the popup, otherwise the full representation will be reparented every time the popup opens or closes
                Item {
                    id: preloadedStorage
                    visible: false
                }

                // Draws a line between the applet dialog and the panel
                KSvg.SvgItem {
                    id: separator
                    // Only draw for popups of panel applets, not desktop applets
                    visible: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.LeftEdge, PlasmaCore.Types.RightEdge, PlasmaCore.Types.BottomEdge]
                        .includes(Plasmoid.location) && !dialog.margin
                    anchors {
                        topMargin: -dialog.topPadding
                        leftMargin: -dialog.leftPadding
                        rightMargin: -dialog.rightPadding
                        bottomMargin: -dialog.bottomPadding
                    }
                    z: 999 /* Draw the line on top of the applet */
                    elementId: (Plasmoid.location === PlasmaCore.Types.TopEdge || Plasmoid.location === PlasmaCore.Types.BottomEdge) ? "horizontal-line" : "vertical-line"
                    imagePath: "widgets/line"
                    // QTBUG-120464: Use AnchorChanges instead of bindings as it's officially supported: https://doc.qt.io/qt-6/qtquick-positioning-anchors.html#changing-anchors
                    states: [
                        State {
                            when: Plasmoid.location === PlasmaCore.Types.TopEdge
                            AnchorChanges {
                                target: separator
                                anchors {
                                    top: separator.parent.top
                                    left: separator.parent.left
                                    right: separator.parent.right
                                }
                            }
                            PropertyChanges {
                                separator.height: 1
                            }
                        },
                        State {
                            when: Plasmoid.location === PlasmaCore.Types.LeftEdge
                            AnchorChanges {
                                target: separator
                                anchors {
                                    left: separator.parent.left
                                    top: separator.parent.top
                                    bottom: separator.parent.bottom
                                }
                            }
                            PropertyChanges {
                                separator.width: 1
                            }
                        },
                        State {
                            when: Plasmoid.location === PlasmaCore.Types.RightEdge
                            AnchorChanges {
                                target: separator
                                anchors {
                                    top: separator.parent.top
                                    right: separator.parent.right
                                    bottom: separator.parent.bottom
                                }
                            }
                            PropertyChanges {
                                separator.width: 1
                            }
                        },
                        State {
                            when: Plasmoid.location === PlasmaCore.Types.BottomEdge
                            AnchorChanges {
                                target: separator
                                anchors {
                                    left: separator.parent.left
                                    right: separator.parent.right
                                    bottom: separator.parent.bottom
                                }
                            }
                            PropertyChanges {
                                separator.height: 1
                            }
                        }
                    ]
                }

                LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
                LayoutMirroring.childrenInherit: true
            }
        }
    }
}
