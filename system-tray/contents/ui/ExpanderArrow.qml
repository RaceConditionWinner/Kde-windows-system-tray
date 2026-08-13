/*
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2015 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmaCore.ToolTipArea {
    id: tooltip

    readonly property int arrowAnimationDuration: Kirigami.Units.shortDuration
    property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    property int iconSize: Kirigami.Units.iconSizes.smallMedium
    implicitWidth: iconSize
    implicitHeight: iconSize
    activeFocusOnTab: true

    Accessible.name: subText
    Accessible.description: i18n("Show all the items in the system tray in a popup")
    Accessible.role: Accessible.Button
    // Keyboard/accessibility activation has no separate press/click phases
    // to snapshot across, so this reads live state (see the TapHandler
    // below for the mouse path, which does need to snapshot).
    Accessible.onPressAction: {
        if (systemTrayState.hiddenItemsShowing) {
            systemTrayState.expanded = false;
        } else {
            systemTrayState.showHiddenItems();
        }
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Enter:
        case Qt.Key_Return:
        case Qt.Key_Select:
            if (systemTrayState.hiddenItemsShowing) {
                systemTrayState.expanded = false;
            } else {
                systemTrayState.showHiddenItems();
            }
        }
    }

    // ExpanderArrow has exactly one job: show the hidden-icons popup. It no
    // longer shows the Action Panel underneath — that's reached only via
    // the system cluster now (PlasmoidItem.qml).
    subText: systemTrayState.hiddenItemsShowing ? i18n("Close popup") : i18n("Show hidden icons")

    property bool wasHiddenItemsShowing

    TapHandler {
        onPressedChanged: {
            if (pressed) {
                // Read at press time, not tap time: hideOnWindowDeactivate
                // can auto-close the popup as soon as this press steals
                // focus from it, before onTapped fires (see
                // systemTrayState.hiddenItemsShowing).
                tooltip.wasHiddenItemsShowing = systemTrayState.hiddenItemsShowing;
            }
        }
        onTapped: (eventPoint, button) => {
            if (tooltip.wasHiddenItemsShowing) {
                systemTrayState.expanded = false;
            } else {
                systemTrayState.showHiddenItems();
            }
            expandedRepresentation.hiddenLayout.currentIndex = -1;
        }
    }

    Kirigami.Icon {
        anchors.fill: parent

        rotation: systemTrayState.hiddenItemsShowing ? 180 : 0
        Behavior on rotation {
            RotationAnimation {
                duration: tooltip.arrowAnimationDuration
            }
        }
        opacity: systemTrayState.hiddenItemsShowing ? 0 : 1
        Behavior on opacity {
            NumberAnimation {
                duration: tooltip.arrowAnimationDuration
            }
        }

        source: {
            if (Plasmoid.location === PlasmaCore.Types.TopEdge) {
                return "arrow-down-symbolic";
            } else if (Plasmoid.location === PlasmaCore.Types.LeftEdge) {
                return "arrow-right-symbolic";
            } else if (Plasmoid.location === PlasmaCore.Types.RightEdge) {
                return "arrow-left-symbolic";
            } else {
                return "arrow-up-symbolic";
            }
        }
    }

    Kirigami.Icon {
        anchors.fill: parent

        rotation: systemTrayState.hiddenItemsShowing ? 0 : -180
        Behavior on rotation {
            RotationAnimation {
                duration: tooltip.arrowAnimationDuration
            }
        }
        opacity: systemTrayState.hiddenItemsShowing ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: tooltip.arrowAnimationDuration
            }
        }

        source: {
            if (Plasmoid.location === PlasmaCore.Types.TopEdge) {
                return "arrow-up-symbolic";
            } else if (Plasmoid.location === PlasmaCore.Types.LeftEdge) {
                return "arrow-left-symbolic";
            } else if (Plasmoid.location === PlasmaCore.Types.RightEdge) {
                return "arrow-right-symbolic";
            } else {
                return "arrow-down-symbolic";
            }
        }
    }
}
