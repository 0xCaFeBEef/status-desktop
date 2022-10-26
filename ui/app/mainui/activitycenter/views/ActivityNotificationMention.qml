import QtQuick 2.14
import QtQuick.Layouts 1.14

import StatusQ.Core 0.1
import StatusQ.Core.Theme 0.1
import StatusQ.Components 0.1

import shared 1.0
import utils 1.0

import "../controls"

ActivityNotificationMessage {
    id: root

    badgeComponent: notification.message.communityId ? communityBadgeComponent : notification.chatId ? groupChatBadgeComponent : null

    Component {
        id: communityBadgeComponent

        CommunityBadge {
            id: communityBadge

            property var community: root.store.getCommunityDetailsAsJson(notification.message.communityId)
            // TODO: here i need chanel
            // property var channel: root.store.getItemAsJson(notification.chatId)

            communityName: community.name
            communityImage: community.image
            communityColor: community.color

            // channelName: channel.name

            onCommunityNameClicked: {
                root.store.setActiveCommunity(notification.message.communityId)
            }
            onChannelNameClicked: {
                root.activityCenterClose()
                root.activityCenterStore.switchTo(notification)
            }
        }
    }

    Component {
        id: groupChatBadgeComponent

        ChannelBadge {
            realChatType: root.realChatType
            textColor: Utils.colorForPubkey(notification.message.senderId)
            name: root.name
            profileImage: Global.getProfileImage(notification.message.chatId)
        }
    }
}