/*
    SPDX-FileCopyrightText: 2015 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2022 ivan tkachenko <me@ratijas.tk>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

import org.kde.kirigami as Kirigami

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

AbstractItem {
    id: plasmoidContainer

    property Item applet: model?.applet ?? null
    text: applet?.Plasmoid.title ?? ""

    itemId: applet?.Plasmoid.pluginName ?? ""
    mainText: applet && (inVisibleLayout || (applet.toolTipMainText && applet.toolTipMainText != text)) ? applet.toolTipMainText : ""
    subText: applet?.toolTipSubText ?? ""
    mainItem: applet?.toolTipItem ?? null
    textFormat: applet?.toolTipTextFormat ?? 0 /* Text.AutoText, the default value */
    active: inVisibleLayout || (systemTrayState.activeApplet !== applet && (text != mainText || subText.length > 0))

    // One of the three Windows 11–style system-cluster applets (Network,
    // Volume, Battery): these never activate their own native/themed popup
    // directly, their primary action is always the shared Action Panel.
    // Right-click context menu, wheel forwarding and tooltips are untouched
    // below — only the primary-activation paths (onActivated/onClicked) are
    // special-cased for this item.
    readonly property bool isSystemClusterItem: applet ? systemTrayState.isSystemClusterApplet(applet) : false

    // See AbstractItem.qml: without this, the reparented native applet
    // (below, via onAppletChanged) can install its own MouseArea that
    // wins primary clicks ahead of this item's onClicked/onPressed,
    // racing with the isSystemClusterItem handling below.
    exclusivePrimaryInput: isSystemClusterItem

    // Snapshot of whether the Action Panel was the thing showing, read at
    // press time rather than click time — see the comment on
    // systemTrayState.actionPanelShowing for why.
    property bool wasActionPanelShowingOnPress: false

    // FIXME: Use an input type agnostic way to activate whatever the primary
    // action of a plasmoid is supposed to be, even if it's just expanding the
    // Plasmoid. Not all plasmoids are supposed to expand and not all plasmoids
    // do anything with onActivated.
    onActivated: pos => {
        if (!applet) {
            return
        }
        if (isSystemClusterItem) {
            // Keyboard/accessibility activation has no separate press/click
            // phases to snapshot across, so read live state here (matching
            // how ExpanderArrow's own keyboard paths do the same).
            if (systemTrayState.actionPanelShowing) {
                systemTrayState.expanded = false
            } else {
                systemTrayState.showActionPanel()
            }
            return
        }
        applet.Plasmoid.activated()
    }

    onClicked: mouse => {
        if (!applet) {
            return
        }
        if (isSystemClusterItem) {
            if (mouse.button === Qt.LeftButton) {
                if (wasActionPanelShowingOnPress) {
                    systemTrayState.expanded = false
                } else {
                    systemTrayState.showActionPanel()
                }
            }
            // Right-click falls through to onContextMenu (via onPressed
            // below), same as every other plasmoid.
            return
        }
        //forward click event to the applet
        const appletItem = applet.compactRepresentationItem ?? applet.fullRepresentationItem
        const mouseArea = findMouseArea(appletItem)

        if (mouseArea && mouse.button !== Qt.RightButton) {
            mouseArea.clicked(mouse)
        } else if (mouse.button === Qt.LeftButton) {//fallback
            activated(null)
        }
    }
    onPressed: mouse => {
        // Only Plasmoids can show context menu on the mouse pressed event.
        // SNI has few problems, for example legacy applications that still use XEmbed require mouse to be released.
        if (mouse.button === Qt.RightButton) {
            contextMenu(mouse);
        } else if (isSystemClusterItem) {
            // Read at press time, not click time: hideOnWindowDeactivate can
            // auto-close the popup as soon as this press steals focus from
            // it, before onClicked fires (see systemTrayState.actionPanelShowing).
            wasActionPanelShowingOnPress = systemTrayState.actionPanelShowing
        } else {
            const appletItem = applet.compactRepresentationItem ?? applet.fullRepresentationItem
            const mouseArea = findMouseArea(appletItem)
            if (mouseArea) {
                // The correct way here would be to invoke the "pressed"
                // signal; however, mouseArea.pressed signal is overridden
                // by its bool value, and our only option is to call the
                // handler directly.
                mouseArea.onPressed(mouse)
            }
        }
    }
    onContextMenu: mouse => {
        if (applet) {
            effectivePressed = false;
            Plasmoid.showPlasmoidMenu(applet, 0, inHiddenLayout ? applet.height : 0);
        }
    }
    onWheel: wheel => {
        if (!applet) {
            return
        }
        //forward wheel event to the applet
        const appletItem = applet.compactRepresentationItem ?? applet.fullRepresentationItem
        const mouseArea = findMouseArea(appletItem)
        if (mouseArea) {
            mouseArea.wheel(wheel)
        }
    }

    function __isSuitableMouseArea(child: Item): bool {
        const item = child.parent;
        return child instanceof MouseArea
            && child.enabled
            // check if MouseArea covers the entire item
            && (child.anchors.fill === item
                || (child.x === 0
                    && child.y === 0
                    && child.width === item.width
                    && child.height === item.height));
    }

    //some heuristics to find MouseArea
    function findMouseArea(item: Item): MouseArea {
        if (!item) {
            return null
        }

        if (item instanceof MouseArea) {
            return item as MouseArea
        }

        return item.children.find(__isSuitableMouseArea) ?? null;
    }

    //This is to make preloading effective, minimizes the scene changes
    function preloadFullRepresentationItem(fullRepresentationItem) {
        if (fullRepresentationItem && fullRepresentationItem.parent === null) {
            fullRepresentationItem.width = expandedRepresentation.width
            fullRepresentationItem.height = expandedRepresentation.height
            fullRepresentationItem.parent = preloadedStorage;
        }
    }

    onAppletChanged: {
        if (applet) {
            applet.parent = iconContainer
            applet.anchors.fill = applet.parent
            applet.visible = true

            preloadFullRepresentationItem(applet.fullRepresentationItem)
        }
    }

    Connections {
        enabled: plasmoidContainer.applet !== null
        target: plasmoidContainer.findMouseArea(
            plasmoidContainer.applet?.compactRepresentationItem ??
            plasmoidContainer.applet?.fullRepresentationItem ??
            plasmoidContainer.applet
        )

        function onContainsPressChanged() {
            plasmoidContainer.effectivePressed = (target as MouseArea).containsPress;
        }

        // TODO For touch/stylus only, since the feature is not desired for mouse users
        function onPressAndHold(mouse) {
            if (mouse.button === Qt.LeftButton) {
                plasmoidContainer.contextMenu(mouse)
            }
        }
    }

    Connections {
        target: plasmoidContainer.applet?.Plasmoid ?? null

        //activation using global keyboard shortcut
        function onActivated() {
            plasmoidContainer.effectivePressed = true;
            Qt.callLater(() => {
                plasmoidContainer.effectivePressed = false;
            });
        }
    }

    Connections {
        target: plasmoidContainer.applet

        function onFullRepresentationItemChanged(fullRepresentationItem) {
            plasmoidContainer.preloadFullRepresentationItem(fullRepresentationItem)
        }

        function onExpandedChanged(expanded) {
            if (expanded) {
                plasmoidContainer.effectivePressed = false;
            }
        }
    }

    PlasmaComponents3.BusyIndicator {
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            leftMargin: plasmoidContainer.inHiddenLayout ? Math.round(Kirigami.Units.smallSpacing / 2) : 0
            right: plasmoidContainer.inHiddenLayout ? undefined : parent.right
        }
        z: 999
        running: plasmoidContainer.applet?.Plasmoid.busy ?? false
    }

    Binding {
        property: "hideOnWindowDeactivate"
        value: !Plasmoid.configuration.pin
        target: plasmoidContainer.applet
        when: plasmoidContainer.applet !== null
        restoreMode: Binding.RestoreBinding
    }
    Binding {
        property: "activeFocusOnTab"
        value: false
        target: plasmoidContainer.applet?.compactRepresentationItem ?? null
        // Also suppressed for cluster items outside the hidden layout:
        // Tab must land on iconContainer (handled by onActivated's
        // isSystemClusterItem branch), never on the native applet's own
        // compactRepresentationItem, which would let Enter/Space activate
        // the native applet directly instead of the Action Panel.
        when: plasmoidContainer?.applet && (plasmoidContainer.inHiddenLayout || plasmoidContainer.isSystemClusterItem)
        restoreMode: Binding.RestoreBinding
    }
    Binding {
        property: "activeFocusOnTab"
        value: false
        target: plasmoidContainer.applet?.fullRepresentationItem ?? null
        when: plasmoidContainer?.applet && (plasmoidContainer.inHiddenLayout || plasmoidContainer.isSystemClusterItem) && !plasmoidContainer.applet.compactRepresentationItem
        restoreMode: Binding.RestoreBinding
    }
}
