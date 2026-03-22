import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "msnap-window-picker"

    Component.onCompleted: activate()

    function activate() {
        pickerPanel.opacity = 0
        pickerPanel.scale = 0.96
        introAnim.restart()
        pickerUI.activate()
    }

    ParallelAnimation {
        id: introAnim
        NumberAnimation {
            target: pickerPanel; property: "opacity"
            to: 1.0; duration: 200; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pickerPanel; property: "scale"
            to: 1.0; duration: 250; easing.type: Easing.OutBack
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: Qt.quit()
    }

    Rectangle {
        id: pickerPanel
        width: 600
        height: 480
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        opacity: 0
        scale: 0.96
        color: "transparent"

        WindowPickerUI {
            id: pickerUI
            anchors.fill: parent

            onWindowSelected: (identifier, title, appId) => {
                Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > /tmp/xdpw-target-window-id", "--", identifier])
                Qt.quit()
            }

            onCancelled: Qt.quit()
        }
    }
}
