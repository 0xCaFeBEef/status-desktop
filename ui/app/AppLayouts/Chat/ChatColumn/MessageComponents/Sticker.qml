import QtQuick 2.3
import "../../../../../shared" as Shared
import "../../../../../imports"

Shared.ImageLoader {
    id: stickerId
    visible: contentType === Constants.stickerType
    width: 140
    height: this.visible ? 140 : 0
    source: this.visible ? ("https://ipfs.infura.io/ipfs/" + sticker) : ""
}
