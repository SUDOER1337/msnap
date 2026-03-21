import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    screen: Quickshell.screens[0]
    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    visible: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "msnap"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    property bool isLoaded: false
    property bool isShot: true
    property string captureMode: "region"
    property bool isCollapsed: false

    property bool optPointer: false
    property bool optAnnotate: false
    property bool optMic: false
    property bool optAudio: false

    property bool isCasting: false
    property bool isTransitioningToCast: false
    property bool showCastAlert: false
    property int castSeconds: 0
    property int castStartEpoch: 0

    readonly property color accent: isShot ? Config.ssAccent : Config.recAccent
    readonly property color pillBg: Qt.rgba(Config.surfaceColor.r, Config.surfaceColor.g, Config.surfaceColor.b, 0.88)

    onIsShotChanged: { 
        if (!isShot && captureMode === "window") captureMode = "region" 
    }

    onCaptureModeChanged: {
        if (!isLoaded) return
        if (captureMode === "region") {
            regionSelector.activate()
        } else {
            regionSelector.visible = false
            // Auto-uncollapse if the user switches to Window or Screen mode
            root.isCollapsed = false
        }
    }

    component IconButton: Rectangle {
        property string iconName: ""
        property bool isActive: false
        property bool isEnabled: true
        property bool isPrimary: false
        property color activeAccent: root.accent
        signal clicked

        width: isPrimary ? 44 : 36
        height: isPrimary ? 44 : 36
        radius: height / 2
        opacity: isEnabled ? 1.0 : 0.3
        color: isPrimary ? activeAccent : (isActive ? Qt.rgba(activeAccent.r, activeAccent.g, activeAccent.b, 0.15) : "transparent")
        border.width: isActive && !isPrimary ? 1 : 0
        border.color: activeAccent

        Icon {
            anchors.centerIn: parent
            name: parent.iconName
            color: parent.isPrimary ? Config.bgColor : (parent.isActive ? parent.activeAccent : Config.textMuted)
            size: parent.isPrimary ? 22 : 20
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.isEnabled
            cursorShape: parent.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }
    }

    component VDivider: Rectangle {
        width: 1
        height: 24
        color: Config.borderColor
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 2
        Layout.rightMargin: 2
    }

    Timer { 
        interval: 50
        running: true
        onTriggered: {
            root.isLoaded = true
            if (root.captureMode === "region") {
                regionSelector.activate()
            }
        }
    }

    FileView {
        id: startTimeFile
        path: "/tmp/msnap-cast.starttime"
        watchChanges: false
        printErrors: false
        onLoaded: {
            const t = parseInt(text().trim(), 10)
            if (!isNaN(t)) root.castStartEpoch = t
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.isCasting
        onTriggered: root.castSeconds = root.castStartEpoch > 0
            ? Math.floor(Date.now() / 1000) - root.castStartEpoch
            : root.castSeconds + 1
        onRunningChanged: {
            if (running) { startTimeFile.reload() }
            else { 
                root.castSeconds = 0
                root.castStartEpoch = 0 
            }
        }
    }

    Timer {
        id: castTransitionTimer
        interval: 400
        repeat: false
        onTriggered: {
            isTransitioningToCast = false
            const a = buildArgs("cast", false)
            a.push("--toggle")
            Quickshell.execDetached(a)
            isCasting = true
            root.visible = false
        }
    }

    FileView {
        path: Config.pidFilePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.isCasting = true
            root.showCastAlert = true
            startTimeFile.reload()
            castAlertTimer.start()
        }
        onLoadFailed: {
            if (root.isCasting) {
                root.isCasting = false
                if (!root.visible) quitTimer.start()
            }
        }
    }

    Timer { 
        id: quitTimer
        interval: 600
        repeat: false
        onTriggered: Qt.quit() 
    }
    
    Timer { 
        id: castAlertTimer
        interval: 2000
        repeat: false
        onTriggered: { 
            root.showCastAlert = false
            root.visible = false 
        }
    }

    function close() { 
        visible = false
        regionSelector.visible = false
        if (!isCasting) Qt.quit() 
    }

    function formatTime(s) {
        const m = Math.floor(s / 60)
        const sec = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
    }

    function buildArgs(sub, forShot) {
        const a = [Config.msnapPath, sub]
        if (captureMode === "region" && regionSelector.hasSelection) {
            const sf = regionSelector.scaleFactor || 1.0
            const rx = Math.round(regionSelector.selX * sf)
            const ry = Math.round(regionSelector.selY * sf)
            const rw = Math.round(regionSelector.selW * sf)
            const rh = Math.round(regionSelector.selH * sf)
            a.push("-g", `${rx},${ry} ${rw}x${rh}`)
        } else if (captureMode === "window") {
            a.push("-w")
        }
        if (forShot) {
            if (optPointer) a.push("-p")
            if (optAnnotate) a.push("-a")
        } else {
            if (optMic) a.push("-m")
            if (optAudio) a.push("-a")
        }
        return a
    }

    function executeAction() {
        if (captureMode === "region" && !regionSelector.hasSelection) {
            return 
        }
        isShot ? doShot() : doCast()
    }

    function doShot() {
        Quickshell.execDetached(buildArgs("shot", true))
        close()
    }

    function doCast() {
        if (isCasting) return
        isTransitioningToCast = true
        regionSelector.visible = false
        castTransitionTimer.start()
    }

    function stopCast() {
        if (!isCasting) return
        Quickshell.execDetached([Config.msnapPath, "cast", "--toggle"])
        isCasting = false
        if (!root.visible) quitTimer.start()
    }

    PanelWindow {
        id: recordingIndicator
        screen: Quickshell.screens[0]
        anchors.bottom: true
        anchors.right: true
        visible: root.isCasting && !root.isTransitioningToCast
        color: "transparent"
        implicitWidth: 240
        implicitHeight: 120

        WlrLayershell.layer:         WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace:     "msnap"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        Item {
            anchors.fill: parent
            anchors.bottomMargin: 40
            anchors.rightMargin: 12

            Rectangle {
                id: pill
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width:  pillHover.containsMouse ? 150 : 6
                height: 44
                radius: pillHover.containsMouse ? 22 : 3
                color:        root.pillBg
                border.width: 1
                border.color: Config.recAccent
                clip: true

                Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                RowLayout {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 150
                    spacing: 12
                    opacity: pillHover.containsMouse ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Rectangle {
                        width: 10; height: 10; radius: 5; color: Config.recAccent; Layout.leftMargin: 16
                        SequentialAnimation on opacity {
                            running: pillHover.containsMouse && root.isCasting
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.formatTime(root.castSeconds)
                        color: Config.textColor
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle { width: 1; height: 16; color: Config.borderColor }

                    Rectangle {
                        width: 32; height: 32; radius: 16; color: "transparent"; Layout.rightMargin: 8
                        Icon { anchors.centerIn: parent; name: "player-stop"; color: Config.recAccent; size: 16 }
                    }
                }

                MouseArea {
                    id: pillHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.stopCast()
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()
        onVisibleChanged: if (visible) forceActiveFocus()

        function cycleTarget(dir) {
            const modes = root.isShot ? ["region", "window", "screen"] : ["region", "screen"]
            const i = modes.indexOf(root.captureMode)
            root.captureMode = modes[((i < 0 ? 0 : i) + dir + modes.length) % modes.length]
        }

        Keys.onTabPressed:     root.isShot = !root.isShot
        Keys.onBacktabPressed: root.isShot = !root.isShot
        Keys.onReturnPressed:  root.executeAction()
        Keys.onEnterPressed:   root.executeAction()
        Keys.onSpacePressed:   root.executeAction()
        Keys.onEscapePressed: {
            if (root.captureMode === "region" && regionSelector.hasSelection) {
                regionSelector.clear()
            } else {
                root.close()
            }
        }

        readonly property var keyHandlers: ({
            [Qt.Key_H]:     () => cycleTarget(-1),
            [Qt.Key_J]:     () => { root.isShot = !root.isShot },
            [Qt.Key_K]:     () => { root.isShot = !root.isShot },
            [Qt.Key_L]:     () => cycleTarget(1),
            [Qt.Key_Left]:  () => cycleTarget(-1),
            [Qt.Key_Right]: () => cycleTarget(1),
            [Qt.Key_S]:     () => { root.isShot = true },
            [Qt.Key_V]:     () => { root.isShot = false },
            [Qt.Key_R]:     () => { root.captureMode = "region" },
            [Qt.Key_W]:     () => { if (root.isShot) root.captureMode = "window" },
            [Qt.Key_F]:     () => { root.captureMode = "screen" },
            [Qt.Key_P]:     () => { if (root.isShot)  root.optPointer  = !root.optPointer },
            [Qt.Key_E]:     () => { if (root.isShot)  root.optAnnotate = !root.optAnnotate },
            [Qt.Key_M]:     () => { if (!root.isShot) root.optMic      = !root.optMic },
            [Qt.Key_A]:     () => { if (!root.isShot) root.optAudio    = !root.optAudio },
        })

        Keys.onPressed: event => {
            const fn = keyHandlers[event.key]
            if (fn) { 
                fn()
                event.accepted = true 
            }
        }

        onActiveFocusChanged: {
            if (!activeFocus && visible && !root.isCasting)
                root.close()
        }

        // ── 1. Global Background Click (Lowest Layer, z: 0) ──
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            enabled: !regionSelector.visible
            onClicked: root.close()
            z: 0 
        }

        // ── 2. The Region Selector (Middle Layer, z: 1) ──────
        RegionSelector {
            id: regionSelector
            anchors.fill: parent
            z: 1 
            scaleFactor: root.screen ? root.screen.devicePixelRatio : 1.0
            onCancelled: root.close()
            onIsActivelyEditingChanged: {
                if (!isActivelyEditing && hasSelection) {
                    root.isCollapsed = false
                }
            }
        }

        // ── 3. Cast Alert Toast (Top Layer, z: 10) ───────────
        Rectangle {
            visible: root.showCastAlert
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: toastRow.implicitWidth + 24
            height: 44
            radius: 22
            color: root.pillBg
            border.color: Config.recAccent
            border.width: 1
            opacity: root.showCastAlert ? 1.0 : 0.0
            z: 10
            Behavior on opacity { NumberAnimation { duration: 200 } }

            RowLayout {
                id: toastRow
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: Config.recAccent
                    SequentialAnimation on opacity {
                        running: root.showCastAlert
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    text: "Recording in progress"
                    color: Config.textColor
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }

        // ── 4. Floating Pull Tab (The Up/Down Toggle) ────────
        Rectangle {
            id: pullTab
            // Only show pull tab during Region Mode!
            visible: !root.showCastAlert && !root.isTransitioningToCast && root.captureMode === "region"
            z: 11 
            width: 48
            height: 24
            radius: 12
            color: root.pillBg
            border.color: Config.borderColor
            border.width: 1

            x: (parent.width - width) / 2
            
            // Explicitly sync Y coordinates with identical math to prevent lag
            y: regionSelector.isActivelyEditing 
                ? parent.height + 10 
                : (root.isCollapsed 
                    ? parent.height - 24 
                    : parent.height - toolbar.idleH - 40 - height + 12)

            // Identical Behavior curve as the toolbar
            Behavior on y { enabled: root.isLoaded; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            Icon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.isCollapsed ? 0 : -2
                name: root.isCollapsed ? "chevron-up" : "chevron-down"
                size: 16
                color: Config.textMuted
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.isCollapsed = !root.isCollapsed
            }
        }

        // ── 5. Floating Toolbar (Top Layer, z: 10) ───────────
        Rectangle {
            id: toolbar
            visible: !root.showCastAlert
            clip: true
            z: 10 

            readonly property real idleW: mainRow.implicitWidth + 32
            readonly property real idleH: 56

            // Dynamic X and Width calculated directly without Behaviors to prevent layout fighting
            x: root.isTransitioningToCast ? parent.width - 6 - 12 : (parent.width - width) / 2
            width: root.isTransitioningToCast ? 6 : idleW
            height: root.isTransitioningToCast ? 44 : idleH
            radius: root.isTransitioningToCast ? 3 : idleH / 2

            // Slide offscreen when dragging region OR when user clicks the pull tab
            y: regionSelector.isActivelyEditing 
                ? parent.height + 10 
                : (root.isCollapsed && root.captureMode === "region" 
                    ? parent.height + 10 
                    : parent.height - idleH - 40)
            
            color: root.pillBg
            border.color: root.isTransitioningToCast ? Config.recAccent : Config.borderColor
            border.width: 1
            opacity: root.isTransitioningToCast ? 0.0 : (regionSelector.isActivelyEditing ? 0.0 : 1.0)

            // ALWAYS animate Y and Opacity for smooth hide/show - matches Pull Tab perfectly
            Behavior on y       { enabled: root.isLoaded; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Behavior on opacity { enabled: root.isLoaded; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            // ONLY animate Width/X/Height during Cast transition. Region expansion handles its own animation cleanly.
            Behavior on width   { enabled: root.isTransitioningToCast; NumberAnimation { duration: 400; easing.type: Easing.InOutCubic } }
            Behavior on height  { enabled: root.isTransitioningToCast; NumberAnimation { duration: 400; easing.type: Easing.InOutCubic } }
            Behavior on x       { enabled: root.isTransitioningToCast; NumberAnimation { duration: 400; easing.type: Easing.InOutCubic } }
            Behavior on radius  { enabled: root.isTransitioningToCast; NumberAnimation { duration: 400; easing.type: Easing.InOutCubic } }

            MouseArea { anchors.fill: parent }

            RowLayout {
                id: mainRow
                anchors.centerIn: parent
                spacing: 8

                IconButton { 
                    iconName: "camera"
                    isActive: root.isShot
                    activeAccent: Config.ssAccent
                    onClicked: root.isShot = true 
                }
                IconButton { 
                    iconName: "video"
                    isActive: !root.isShot
                    activeAccent: Config.recAccent
                    onClicked: root.isShot = false 
                }

                VDivider {}

                Rectangle {
                    id: regionBtn
                    height: 36
                    Layout.preferredWidth: (root.captureMode === "region" && regionSelector.hasSelection) ? regionBtnRow.implicitWidth + 16 : 36
                    radius: 18
                    color: root.captureMode === "region" ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
                    border.width: root.captureMode === "region" ? 1 : 0
                    border.color: root.accent

                    // This is the ONLY width behavior needed. It smoothly pushes the RowLayout.
                    Behavior on Layout.preferredWidth { 
                        enabled: root.isLoaded
                        NumberAnimation { duration: 350; easing.type: Easing.OutCubic } 
                    }

                    RowLayout {
                        id: regionBtnRow
                        anchors.centerIn: parent
                        spacing: 5

                        Icon {
                            name: "crop"
                            size: 20
                            color: root.captureMode === "region" ? root.accent : Config.textMuted
                        }

                        Text {
                            visible: root.captureMode === "region" && regionSelector.hasSelection
                            text: Math.round(regionSelector.selW * (regionSelector.scaleFactor || 1.0)) + " × " + Math.round(regionSelector.selH * (regionSelector.scaleFactor || 1.0))
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: root.accent
                            Layout.rightMargin: 2
                        }

                        Icon {
                            visible: root.captureMode === "region" && regionSelector.hasSelection
                            name: "restore"
                            size: 12
                            color: root.accent
                            opacity: 0.7
                            Layout.rightMargin: 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.captureMode = "region"
                            if (regionSelector.hasSelection) {
                                regionSelector.clear()
                            }
                        }
                    }
                }

                IconButton { 
                    iconName: "app-window"
                    isActive: root.captureMode === "window"
                    isEnabled: root.isShot
                    onClicked: root.captureMode = "window" 
                }
                IconButton { 
                    iconName: "device-desktop"
                    isActive: root.captureMode === "screen"
                    onClicked: root.captureMode = "screen" 
                }

                VDivider {}

                IconButton {
                    iconName: root.isShot ? (root.optPointer ? "pointer" : "pointer-off") : (root.optMic ? "microphone" : "microphone-off")
                    isActive: root.isShot ? root.optPointer : root.optMic
                    onClicked: root.isShot ? (root.optPointer = !root.optPointer) : (root.optMic = !root.optMic)
                }
                IconButton {
                    iconName: root.isShot ? (root.optAnnotate ? "pencil" : "pencil-off") : (root.optAudio ? "volume" : "volume-3")
                    isActive: root.isShot ? root.optAnnotate : root.optAudio
                    onClicked: root.isShot ? (root.optAnnotate = !root.optAnnotate) : (root.optAudio = !root.optAudio)
                }

                VDivider {}

                IconButton {
                    isPrimary: true
                    iconName: root.captureMode === "region" && !regionSelector.hasSelection ? "crop" : root.isShot ? "camera-up" : "player-record"
                    onClicked: root.executeAction()
                }
            }
        }
    }
}
