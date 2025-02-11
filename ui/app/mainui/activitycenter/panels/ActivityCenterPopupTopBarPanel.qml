import QtQuick 2.14
import QtQuick.Controls 2.14
import QtQuick.Layouts 1.14

import utils 1.0

import StatusQ.Core 0.1
import StatusQ.Core.Theme 0.1
import StatusQ.Controls 0.1
import StatusQ.Popups 0.1

import "../popups"

Item {
    id: root

    property bool hasAdmin: false
    property bool hasMentions: false
    property bool hasReplies: false
    property bool hasContactRequests: false
    property bool hasMembership: false

    property bool hideReadNotifications: false
    property int unreadNotificationsCount: 0

    property int currentActivityCategory: ActivityCenterPopup.ActivityCategory.All

    property alias errorText: errorText.text

    signal categoryTriggered(int category)
    signal markAllReadClicked()
    signal showHideReadNotifications(bool hideReadNotifications)

    height: 64

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Style.current.padding
        anchors.rightMargin: Style.current.padding
        spacing: Style.current.padding

        StatusRollArea {
            Layout.fillWidth: true

            content: RowLayout {
                spacing: 0

                Repeater {
                    // NOTE: some entries are hidden until implimentation
                    model: [ { text: qsTr("All"), category: ActivityCenterPopup.ActivityCategory.All, visible: true, enabled: true },
                            { text: qsTr("Admin"), category: ActivityCenterPopup.ActivityCategory.Admin, visible: root.hasAdmin, enabled: root.hasAdmin },
                            { text: qsTr("Mentions"), category: ActivityCenterPopup.ActivityCategory.Mentions, visible: true, enabled: root.hasMentions },
                            { text: qsTr("Replies"), category: ActivityCenterPopup.ActivityCategory.Replies, visible: true, enabled: root.hasReplies },
                            { text: qsTr("Contact requests"), category: ActivityCenterPopup.ActivityCategory.ContactRequests, visible: true, enabled: root.hasContactRequests },
                            { text: qsTr("Identity verification"), category: ActivityCenterPopup.ActivityCategory.IdentityVerification, visible: false, enabled: true },
                            { text: qsTr("Transactions"), category: ActivityCenterPopup.ActivityCategory.Transactions, visible: false, enabled: true },
                            { text: qsTr("Membership"), category: ActivityCenterPopup.ActivityCategory.Membership, visible: true, enabled: root.hasMembership },
                            { text: qsTr("System"), category: ActivityCenterPopup.ActivityCategory.System, visible: false, enabled: true } ]

                    StatusFlatButton {
                        enabled: modelData.enabled
                        visible: modelData.visible
                        text: modelData.text
                        size: StatusBaseButton.Size.Small
                        highlighted: modelData.category === root.currentActivityCategory
                        onClicked: root.categoryTriggered(modelData.category)
                        onEnabledChanged: if (!enabled && highlighted) root.categoryTriggered(ActivityCenterPopup.ActivityCategory.All)
                        Layout.preferredWidth: visible ? implicitWidth : 0
                    }
                }
            }
        }

        StatusFlatRoundButton {
            id: markAllReadBtn
            enabled: root.unreadNotificationsCount > 0
            icon.name: "double-checkmark"
            onClicked: root.markAllReadClicked()

            StatusToolTip {
                visible: markAllReadBtn.hovered
                text: qsTr("Mark all as Read")
            }
        }

        StatusFlatRoundButton {
            id: hideReadNotificationsBtn
            icon.name: root.hideReadNotifications ? "hide" : "show"
            onClicked: root.showHideReadNotifications(!root.hideReadNotifications)

            StatusToolTip {
                visible: hideReadNotificationsBtn.hovered
                offset: width / 4
                text: root.hideReadNotifications ? qsTr("Show read notifications") : qsTr("Hide read notifications")
            }
        }
    }

    StatusBaseText {
        id: errorText
        visible: !!text
        anchors.top: parent.top
        anchors.topMargin: Style.current.smallPadding
        color: Theme.palette.dangerColor1
    }
}
