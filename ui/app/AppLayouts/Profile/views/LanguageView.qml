import QtQuick 2.13
import QtQuick.Controls 2.13
import QtQuick.Layouts 1.13

import utils 1.0
import shared.panels 1.0
import shared.popups 1.0

import StatusQ.Core 0.1
import StatusQ.Core.Theme 0.1
import StatusQ.Components 0.1

import "../popups"
import "../stores"

Item {
    id: root

    property LanguageStore languageStore
    property var currencyStore
    property int profileContentWidth

    QtObject {
        id: d
        property int margins: 64
        property int zOnTop: 100

        function setViewIdleState() {
            currencyPicker.close()
            languagePicker.close()
        }
    }

    z: d.zOnTop
    Layout.fillHeight: true
    Layout.fillWidth: true
    clip: true

    onVisibleChanged: { if(!visible) d.setViewIdleState()}

    Component.onCompleted: {
        root.currencyStore.updateCurrenciesModel()
        root.languageStore.initializeLanguageModel()
    }

    Column {
        z: d.zOnTop
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: d.margins
        anchors.left: parent.left
        spacing: 45

        StatusBaseText {
            id: title
            text: qsTr("Language & Currency")
            font.weight: Font.Bold
            font.pixelSize: 22
            color: Theme.palette.directColor1
        }

        Column {
            z: d.zOnTop
            width: 560 - (2 * Style.current.padding)
            spacing: 26

            Item {
                id: currency
                width: parent.width
                height: 38
                z: d.zOnTop + 1

                StatusBaseText {
                    text: qsTr("Set Display Currency")
                    anchors.left: parent.left
                    font.pixelSize: 15
                    color: Theme.palette.directColor1
                }
                StatusListPicker {
                    id: currencyPicker

                    property string newKey

                    Timer {
                        id: currencyPause
                        interval: 100
                        onTriggered: {
                            // updateCurrency function operation blocks a little bit the UI so getting around it with a small pause (timer) in order to get the desired visual behavior
                            root.currencyStore.updateCurrency(currencyPicker.newKey)
                        }
                    }

                    z: d.zOnTop + 1
                    width: 104
                    height: parent.height
                    anchors.right: parent.right
                    inputList: root.currencyStore.currenciesModel
                    printSymbol: true
                    placeholderSearchText: qsTr("Search Currencies")

                    onItemPickerChanged: {
                        if(selected) {
                            currencyPicker.newKey = key
                            currencyPause.start()
                        }
                    }
                }
            }

            Item {
                id: language
                width: parent.width
                height: 38
                z: d.zOnTop

                StatusBaseText {
                    text: qsTr("Language")
                    anchors.left: parent.left
                    font.pixelSize: 15
                    color: Theme.palette.directColor1
                }
                StatusListPicker {
                    id: languagePicker

                    property string newKey

                    Timer {
                        id: languagePause
                        interval: 100
                        onTriggered: {
                            // changeLocale function operation blocks a little bit the UI so getting around it with a small pause (timer) in order to get the desired visual behavior
                            root.languageStore.changeLocale(languagePicker.newKey)
                        }
                    }

                    z: d.zOnTop
                    width: 104
                    height: parent.height
                    anchors.right: parent.right
                    inputList: root.languageStore.languageModel
                    placeholderSearchText: qsTr("Search Languages")

                    onItemPickerChanged: {
                        if(selected && localAppSettings.locale !== key) {
                            // TEMPORARY: It should be removed as it is only used in Linux OS but it must be investigated how to change language in execution time, as well, in Linux (will be addressed in another task)
                            if (Qt.platform.os === Constants.linux) {
                                    linuxConfirmationDialog.active = true
                                    linuxConfirmationDialog.item.newLocale = key
                                    linuxConfirmationDialog.item.open()
                            }
                            else {
                                languagePicker.newKey = key
                                languagePause.start()
                            }
                        }
                    }
                }
            }

            Separator {
                anchors.left: parent.left
                anchors.leftMargin: -Style.current.padding
                anchors.right: parent.right
                anchors.rightMargin: -Style.current.padding
            }
        }
    }

    // TEMPORARY: It should be removed as it is only used in Linux OS but it must be investigated how to change language in execution time, as well, in Linux (will be addressed in another task)
    Loader {
        id: linuxConfirmationDialog
        active: false
        sourceComponent: ConfirmationDialog {
           property string newLocale

           header.title: qsTr("Change language")
           confirmationText: qsTr("Display language has been changed. You must restart the application for changes to take effect.")
           confirmButtonLabel: qsTr("Close the app now")
           onConfirmButtonClicked: {
               root.languageStore.changeLocale(newLocale)
               loader.active = false
               Qt.quit()
           }
       }
    }

    // Outsite area
    MouseArea {
        anchors.fill: parent
        onClicked: { d.setViewIdleState() }
    }
}
