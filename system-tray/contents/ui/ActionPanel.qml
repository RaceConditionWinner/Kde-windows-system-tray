/*
    Action Panel — quick-toggle tiles + sliders shown in the expander popup.

    A Windows 11 / 10 hybrid. The hidden SNI icons grid and footer are
    composed by ExpandedRepresentation around this component.
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "components" as Components

ColumnLayout {
    id: actionPanel

    signal requestPage(string name)

    readonly property real scale: Plasmoid.configuration.scale / 100

    Layout.fillWidth: true
    spacing: 16 * actionPanel.scale

    // Display-only identity header. Uses QtCore only, avoiding optional KDE QML modules.
    readonly property string homePath: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string userName: homePath.substring(homePath.lastIndexOf("/") + 1)

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 18 * actionPanel.scale
        Layout.rightMargin: 18 * actionPanel.scale
        Layout.topMargin: 12 * actionPanel.scale
        Layout.preferredHeight: 44 * actionPanel.scale
        spacing: 10 * actionPanel.scale

        Rectangle {
            Layout.preferredWidth: 40 * actionPanel.scale
            Layout.preferredHeight: 40 * actionPanel.scale
            radius: width / 2
            
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.08)

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 22 * actionPanel.scale
                height: width
                source: "user-identity"
                color: Kirigami.Theme.textColor
                visible: userFace.status !== Image.Ready
            }

            Image {
                id: userFace
                anchors.fill: parent
                anchors.margins: 2 * actionPanel.scale
                source: "file:///var/lib/AccountsService/icons/" + actionPanel.userName
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1 * actionPanel.scale

            Text {
                Layout.fillWidth: true
                text: actionPanel.userName
                color: Kirigami.Theme.textColor
                font.pixelSize: 15 * actionPanel.scale
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Local account")
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 11 * actionPanel.scale
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    Components.QuickSettingsPager {
        Layout.fillWidth: true
        Layout.leftMargin: 14 * actionPanel.scale
        Layout.rightMargin: 14 * actionPanel.scale
        Layout.topMargin: 6 * actionPanel.scale
        uiScale: actionPanel.scale
        onRequestPage: name => actionPanel.requestPage(name)
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 14 * actionPanel.scale
        Layout.rightMargin: 14 * actionPanel.scale
        Layout.bottomMargin: 14 * actionPanel.scale
        columns: 3
        rowSpacing: 12 * actionPanel.scale
        columnSpacing: 0

        Components.BrightnessSlider {
            Layout.fillWidth: true
            Layout.columnSpan: 3
            visible: Plasmoid.configuration.showBrightness
            showArrow: true
            panelScreenGeometry: Plasmoid.screenGeometry
            panelScreenIndex: Plasmoid.containment.screen
            onArrowClicked: actionPanel.requestPage("brightness")
        }
        Components.VolumeSlider {
            Layout.fillWidth: true
            Layout.columnSpan: 3
            Layout.preferredHeight: 36
            visible: Plasmoid.configuration.showVolume
            onArrowClicked: actionPanel.requestPage("volume")
        }
    }
}
