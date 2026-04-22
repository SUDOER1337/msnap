import QtQuick

Item {
    id: root
    anchors.fill: parent
    visible: false

    property real scaleFactor: 1.0

    signal cancelled

    property bool isSelecting: false
    property bool isMoving: false
    property bool isResizing: false
    property int activeHandle: -1

    readonly property bool isActivelyEditing: isSelecting || isMoving || isResizing

    property int startX: 0
    property int startY: 0

    property int selX: 0
    property int selY: 0
    property int selW: 0
    property int selH: 0

    property int moveStartSelX: 0
    property int moveStartSelY: 0
    property int moveStartMouseX: 0
    property int moveStartMouseY: 0

    property int resizeAnchorX: 0
    property int resizeAnchorY: 0

    readonly property bool hasSelection: selW > 4 && selH > 4

    readonly property color overlayMask: Qt.rgba(
        Config.overlayColor.r,
        Config.overlayColor.g,
        Config.overlayColor.b,
        Config.overlayAlpha
    )
    readonly property color dimLabelBg: Qt.rgba(
        Config.dimLabelBg.r,
        Config.dimLabelBg.g,
        Config.dimLabelBg.b,
        Config.dimLabelAlpha
    )
    readonly property color instructionTextColor: Qt.rgba(
        Config.instructionColor.r,
        Config.instructionColor.g,
        Config.instructionColor.b,
        Config.instructionAlpha
    )

    readonly property var handlePositions: [
        { x: 0, y: 0, cursor: Qt.SizeFDiagCursor }, 
        { x: 1, y: 0, cursor: Qt.SizeBDiagCursor }, 
        { x: 0, y: 1, cursor: Qt.SizeBDiagCursor }, 
        { x: 1, y: 1, cursor: Qt.SizeFDiagCursor }  
    ]

    readonly property var anchorOffsets: [
        { x: 1, y: 1 }, 
        { x: 0, y: 1 }, 
        { x: 1, y: 0 }, 
        { x: 0, y: 0 }  
    ]

    readonly property int defaultSelWidth: 400
    readonly property int defaultSelHeight: 300
    readonly property int handleSize: 12
    readonly property int handleHitArea: 6
    readonly property int minSelectionSize: 8

    function activate() {
        isSelecting = false
        isMoving = false
        isResizing = false
        activeHandle = -1
        visible = true
    }

    function clear() {
        selW = 0
        selH = 0
        isSelecting = false
        isMoving = false
        isResizing = false
        activeHandle = -1
    }

    Rectangle {
        anchors.fill: parent
        color: root.overlayMask
        z: 0
    }

    Rectangle {
        x: root.selX
        y: root.selY
        width: root.selW
        height: root.selH
        visible: root.hasSelection
        color: "transparent"
        z: 1
    }

    Rectangle {
        x: 0
        y: 0
        width: root.width
        height: root.hasSelection ? root.selY : root.height
        color: root.overlayMask
        z: 2
        visible: root.hasSelection
    }

    Rectangle {
        x: 0
        y: root.hasSelection ? root.selY + root.selH : root.height
        width: root.width
        height: root.hasSelection ? root.height - (root.selY + root.selH) : 0
        color: root.overlayMask
        z: 2
        visible: root.hasSelection
    }

    Rectangle {
        x: 0
        y: root.selY
        width: root.hasSelection ? root.selX : 0
        height: root.selH
        color: root.overlayMask
        z: 2
        visible: root.hasSelection
    }

    Rectangle {
        x: root.selX + root.selW
        y: root.selY
        width: root.hasSelection ? root.width - (root.selX + root.selW) : 0
        height: root.selH
        color: root.overlayMask
        z: 2
        visible: root.hasSelection
    }

    Rectangle {
        x: root.selX
        y: root.selY
        width: root.selW
        height: root.selH
        visible: root.hasSelection
        color: "transparent"
        border.width: 2
        border.color: Config.ssAccent
        z: 5
    }

    Rectangle {
        visible: root.hasSelection
        x: Math.min(Math.max(root.selX + 8, 8), root.width - width - 8)
        y: root.selY > 38 ? root.selY - 32 : root.selY + root.selH + 8
        width: dimText.implicitWidth + 16
        height: 24
        radius: 12
        color: root.dimLabelBg
        z: 10

        Text {
            id: dimText
            anchors.centerIn: parent
            text: Math.round(root.selW * root.scaleFactor) + " × " + Math.round(root.selH * root.scaleFactor) + " px"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: Config.handleColor
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        text: root.hasSelection ? "Drag to move  ·  Corners to resize  ·  Enter to confirm  ·  Esc to cancel" : "Drag to select  ·  Esc to cancel"
        font.pixelSize: 11
        color: root.instructionTextColor
        z: 10
    }

    Repeater {
        model: root.handlePositions

        delegate: Rectangle {
            required property var modelData
            required property int index

            readonly property int hx: modelData.x === 0 ? root.selX : root.selX + root.selW
            readonly property int hy: modelData.y === 0 ? root.selY : root.selY + root.selH

            x: hx - root.handleSize / 2
            y: hy - root.handleSize / 2
            width: root.handleSize
            height: root.handleSize
            radius: root.handleSize / 2
            visible: root.hasSelection && !root.isSelecting
            color: Config.handleColor
            border.width: 2
            border.color: Config.ssAccent
            z: 12

            MouseArea {
                anchors { fill: parent; margins: -root.handleHitArea }
                cursorShape: modelData.cursor
                hoverEnabled: true

                onPressed: mouse => {
                    root.isResizing = true
                    root.activeHandle = index
                    const offset = root.anchorOffsets[index]
                    root.resizeAnchorX = root.selX + offset.x * root.selW
                    root.resizeAnchorY = root.selY + offset.y * root.selH
                }

                onPositionChanged: mouse => {
                    if (!root.isResizing || root.activeHandle !== index) return
                    const pt = mapToItem(root, mouse.x, mouse.y)
                    const ax = root.resizeAnchorX
                    const ay = root.resizeAnchorY

                    const nx = Math.min(pt.x, ax)
                    const ny = Math.min(pt.y, ay)
                    const nw = Math.abs(pt.x - ax)
                    const nh = Math.abs(pt.y - ay)

                    if (nw >= root.minSelectionSize && nh >= root.minSelectionSize) {
                        root.selX = nx
                        root.selY = ny
                        root.selW = nw
                        root.selH = nh
                    }
                }

                onReleased: {
                    root.isResizing = false
                    root.activeHandle = -1
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        z: 3

        cursorShape: {
            if (root.isSelecting) return Qt.CrossCursor
            if (root.isMoving) return Qt.ClosedHandCursor
            if (root.hasSelection && mouseX >= root.selX && mouseX <= root.selX + root.selW && mouseY >= root.selY && mouseY <= root.selY + root.selH) {
                return Qt.OpenHandCursor
            }
            return Qt.CrossCursor
        }

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.hasSelection) root.clear()
                else root.cancelled()
            }
        }

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton || root.isResizing) return
            const inSel = root.hasSelection && mouse.x >= root.selX && mouse.x <= root.selX + root.selW && mouse.y >= root.selY && mouse.y <= root.selY + root.selH
            
            if (inSel) {
                root.isMoving = true
                root.moveStartSelX = root.selX
                root.moveStartSelY = root.selY
                root.moveStartMouseX = mouse.x
                root.moveStartMouseY = mouse.y
            } else {
                root.isSelecting = true
                root.startX = mouse.x
                root.startY = mouse.y
                root.selX = mouse.x
                root.selY = mouse.y
                root.selW = 0
                root.selH = 0
            }
        }

        onPositionChanged: mouse => {
            if (root.isSelecting) {
                root.selX = Math.min(mouse.x, root.startX)
                root.selY = Math.min(mouse.y, root.startY)
                root.selW = Math.abs(mouse.x - root.startX)
                root.selH = Math.abs(mouse.y - root.startY)
                return
            }

            if (root.isMoving) {
                const dx = mouse.x - root.moveStartMouseX
                const dy = mouse.y - root.moveStartMouseY
                const maxX = root.width - root.selW
                const maxY = root.height - root.selH
                
                root.selX = Math.max(0, Math.min(root.moveStartSelX + dx, maxX))
                root.selY = Math.max(0, Math.min(root.moveStartSelY + dy, maxY))
            }
        }

        onReleased: mouse => {
            if (mouse.button === Qt.LeftButton) {
                root.isSelecting = false
                root.isMoving = false
            }
        }
    }
}
