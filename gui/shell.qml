import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
  id: root

  screen: Quickshell.screens[0]
  anchors.top: true; anchors.left: true
  anchors.right: true; anchors.bottom: true
  visible: true
  color: "transparent"

  WlrLayershell.layer:         WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  WlrLayershell.namespace:     "msnap"
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  //  State 
  property bool   isLoaded:    false   // suppresses startup animation snap
  property bool   isShot:      true
  property string captureMode: "region"

  property bool optPointer:  false
  property bool optAnnotate: false
  property bool optMic:      false
  property bool optAudio:    false

  // selX/Y/W/H  — physical px (display in dim badge)
  // regionSel*  — logical px  (passed to CLI -g flag)
  property bool isRegionSelected: false
  property int  selX: 0;       property int selY: 0
  property int  selW: 0;       property int selH: 0
  property int  regionSelX: 0; property int regionSelY: 0
  property int  regionSelW: 0; property int regionSelH: 0

  property bool isCasting:             false
  property bool isTransitioningToCast: false
  property bool showCastAlert:         false
  property int  castSeconds:           0
  property int  castStartEpoch:        0

  //  Derived 
  readonly property color accent: isShot ? Config.ssAccent : Config.recAccent
  readonly property color pillBg: Qt.rgba(Config.surfaceColor.r,
                                          Config.surfaceColor.g,
                                          Config.surfaceColor.b, 0.88)

  onIsShotChanged: { if (!isShot && captureMode === "window") captureMode = "region" }

  //  Inline components 
  component IconButton: Rectangle {
    property string iconName:     ""
    property bool   isActive:     false
    property bool   isEnabled:    true
    property bool   isPrimary:    false
    property color  activeAccent: root.accent
    signal clicked

    width:  isPrimary ? 44 : 36
    height: isPrimary ? 44 : 36
    radius: height / 2
    opacity: isEnabled ? 1.0 : 0.3
    color: isPrimary  ? activeAccent
         : isActive   ? Qt.rgba(activeAccent.r, activeAccent.g, activeAccent.b, 0.15)
         : "transparent"
    border.width: isActive && !isPrimary ? 1 : 0
    border.color: activeAccent

    Icon {
      anchors.centerIn: parent
      name:  parent.iconName
      color: parent.isPrimary  ? Config.bgColor
           : parent.isActive   ? parent.activeAccent
           : Config.textMuted
      size:  parent.isPrimary ? 22 : 20
    }

    MouseArea {
      anchors.fill: parent
      enabled:      parent.isEnabled
      cursorShape:  parent.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked:    parent.clicked()
    }
  }

  component VDivider: Rectangle {
    width: 1; height: 24
    color: Config.borderColor
    Layout.alignment: Qt.AlignVCenter
  }

  //  Services 

  // Startup guard — prevents behaviors from animating on initial render
  Timer { interval: 50; running: true; onTriggered: root.isLoaded = true }

  // Cast starttime — written by cast_command.sh as unix epoch
  FileView {
    id: startTimeFile
    path: "/tmp/msnap-cast.starttime"
    watchChanges: false; printErrors: false
    onLoaded: {
      const t = parseInt(text().trim(), 10)
      if (!isNaN(t)) root.castStartEpoch = t
    }
  }

  // Cast elapsed timer — derives from epoch when available, increments otherwise
  Timer {
    interval: 1000; repeat: true; running: root.isCasting
    onTriggered: root.castSeconds = root.castStartEpoch > 0
      ? Math.floor(Date.now() / 1000) - root.castStartEpoch
      : root.castSeconds + 1
    onRunningChanged: {
      if (running) { startTimeFile.reload() }
      else { root.castSeconds = 0; root.castStartEpoch = 0 }
    }
  }

  // Cast launch — brief animation then exec
  Timer {
    id: castTransitionTimer
    interval: 400; repeat: false
    onTriggered: {
      isTransitioningToCast = false
      const a = buildArgs("cast", false)
      a.push("--toggle")
      Quickshell.execDetached(a)
      isCasting = true
      root.visible = false
    }
  }

  // PID watcher — source of truth for cast state
  FileView {
    path: Config.pidFilePath; watchChanges: true; printErrors: false
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

  Timer { id: quitTimer;      interval: 600;  repeat: false; onTriggered: Qt.quit() }
  Timer { id: castAlertTimer; interval: 2000; repeat: false
    onTriggered: { root.showCastAlert = false; root.visible = false }
  }

  //  Helpers 
  function close() { visible = false; if (!isCasting) Qt.quit() }

  function formatTime(s) {
    const m = Math.floor(s / 60), sec = s % 60
    return (m   < 10 ? "0" : "") + m   + ":"
         + (sec < 10 ? "0" : "") + sec
  }

  function buildArgs(sub, forShot) {
    const a = [Config.msnapPath, sub]
    if (captureMode === "region" && isRegionSelected)
      a.push("-g", `${regionSelX},${regionSelY} ${regionSelW}x${regionSelH}`)
    else if (captureMode === "window")
      a.push("-w")
    if (forShot) {
      if (optPointer)  a.push("-p")
      if (optAnnotate) a.push("-a")
    } else {
      if (optMic)   a.push("-m")
      if (optAudio) a.push("-a")
    }
    return a
  }

  function executeAction() {
    if (captureMode === "region" && !isRegionSelected) {
      regionSelector.open(regionSelX, regionSelY, regionSelW, regionSelH)
      root.visible = false
      return
    }
    isShot ? doShot() : doCast()
  }

  function doShot() {
    Quickshell.execDetached(buildArgs("shot", true))
    close()
  }

  function doCast() {
    if (isCasting) return   // already recording — pill handles stop
    isTransitioningToCast = true
    castTransitionTimer.start()
  }

  function reEditRegion() {
    regionSelector.open(regionSelX, regionSelY, regionSelW, regionSelH)
    root.visible = false
  }

  function stopCast() {
    if (!isCasting) return
    Quickshell.execDetached([Config.msnapPath, "cast", "--toggle"])
    isCasting = false
    if (!root.visible) quitTimer.start()
  }

  //  Region selector 
  RegionSelector {
    id: regionSelector
    onSelectionComplete: (x, y, w, h, quick) => {
      selX = x; selY = y; selW = w; selH = h
      isRegionSelected = true
      const sf = scaleFactor || 1
      regionSelX = Math.round(x / sf); regionSelY = Math.round(y / sf)
      regionSelW = Math.round(w / sf); regionSelH = Math.round(h / sf)
      close()
      root.visible = true
      if (quick) root.executeAction()
    }
    onCancelled: root.visible = true
  }

  // ══════════════════════════════════════════════════════
  // RECORDING PILL
  // Collapsed: 6 × 44 px red bar, anchored bottom-right
  // Hover: expands to show elapsed time + stop button
  // ══════════════════════════════════════════════════════
  PanelWindow {
    id: recordingIndicator
    screen: Quickshell.screens[0]
    anchors.bottom: true; anchors.right: true
    visible: root.isCasting && !root.isTransitioningToCast
    color: "transparent"
    implicitWidth: 240; implicitHeight: 120

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace:     "msnap"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Item {
      anchors.fill: parent
      anchors.bottomMargin: 40; anchors.rightMargin: 12

      Rectangle {
        id: pill
        anchors.bottom: parent.bottom; anchors.right: parent.right

        width:  pillHover.containsMouse ? 150 : 6
        height: 44
        radius: pillHover.containsMouse ? 22  : 3

        color:        root.pillBg
        border.width: 1
        border.color: Config.recAccent
        clip: true

        Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on radius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        RowLayout {
          anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
          width: 150; spacing: 12
          opacity: pillHover.containsMouse ? 1.0 : 0.0
          Behavior on opacity { NumberAnimation { duration: 200 } }

          // Pulsing dot
          Rectangle {
            width: 10; height: 10; radius: 5
            color: Config.recAccent
            Layout.leftMargin: 16
            SequentialAnimation on opacity {
              running: pillHover.containsMouse && root.isCasting
              loops: Animation.Infinite
              NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
            }
          }

          // Elapsed time
          Text {
            Layout.fillWidth: true
            text:                root.formatTime(root.castSeconds)
            color:               Config.textColor
            font.pixelSize:      13; font.weight: Font.DemiBold
            verticalAlignment:   Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
          }

          Rectangle { width: 1; height: 16; color: Config.borderColor }

          // Stop button
          Rectangle {
            width: 32; height: 32; radius: 16
            color: "transparent"; Layout.rightMargin: 8
            Icon { anchors.centerIn: parent; name: "player-stop"; color: Config.recAccent; size: 16 }
          }
        }

        MouseArea {
          id: pillHover
          anchors.fill: parent; hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.stopCast()
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════
  // MAIN OVERLAY
  // ══════════════════════════════════════════════════════
  Item {
    anchors.fill: parent
    focus: true
    Component.onCompleted: forceActiveFocus()
    onVisibleChanged: if (visible) forceActiveFocus()

    //  Keyboard 
    //  Tab / Shift-Tab   toggle shot ↔ cast
    //  H/L  ←/→          cycle capture target
    //  S / V              shot / cast direct
    //  R / W / F          region / window / fullscreen direct
    //  P / E              shot: pointer / annotate
    //  M / A              cast: mic / audio
    //  Enter              execute
    //  Esc                close panel
    function cycleTarget(dir) {
      const modes = root.isShot
        ? ["region", "window", "screen"]
        : ["region", "screen"]
      const i = modes.indexOf(root.captureMode)
      root.captureMode = modes[((i < 0 ? 0 : i) + dir + modes.length) % modes.length]
    }

    Keys.onTabPressed:     root.isShot = !root.isShot
    Keys.onBacktabPressed: root.isShot = !root.isShot
    Keys.onReturnPressed:  root.executeAction()
    Keys.onEnterPressed:   root.executeAction()
    Keys.onEscapePressed:  root.close()

    // Declared as property so the object is created once, not on every keypress
    readonly property var keyHandlers: ({
      [Qt.Key_H]:     () => cycleTarget(-1),
      [Qt.Key_L]:     () => cycleTarget(1),
      [Qt.Key_Left]:  () => cycleTarget(-1),
      [Qt.Key_Right]: () => cycleTarget(1),
      [Qt.Key_S]:     () => { root.isShot = true },
      [Qt.Key_V]:     () => { root.isShot = false },
      [Qt.Key_R]: () => {
          if (root.captureMode === "region" && root.isRegionSelected)
            root.reEditRegion()
          else
            root.captureMode = "region"
        },
      [Qt.Key_W]:     () => { if (root.isShot) root.captureMode = "window" },
      [Qt.Key_F]:     () => { root.captureMode = "screen" },
      [Qt.Key_P]:     () => { if (root.isShot)  root.optPointer  = !root.optPointer },
      [Qt.Key_E]:     () => { if (root.isShot)  root.optAnnotate = !root.optAnnotate },
      [Qt.Key_M]:     () => { if (!root.isShot) root.optMic      = !root.optMic },
      [Qt.Key_A]:     () => { if (!root.isShot) root.optAudio    = !root.optAudio },
    })

    Keys.onPressed: event => {
      // Shift+R — redraw region from scratch
      if (event.key === Qt.Key_R && (event.modifiers & Qt.ShiftModifier)) {
        root.isRegionSelected = false
        root.captureMode = "region"
        root.reEditRegion()
        event.accepted = true
        return
      }
      const fn = keyHandlers[event.key]
      if (fn) { fn(); event.accepted = true }
    }

    onActiveFocusChanged: {
      if (!activeFocus && visible && !regionSelector.visible && !root.isCasting)
        root.close()
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: root.close()

      //  Cast alert toast 
      Rectangle {
        visible: root.showCastAlert
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 40
        width: toastRow.implicitWidth + 24; height: 44; radius: 22
        color: root.pillBg
        border.color: Config.recAccent; border.width: 1
        opacity: root.showCastAlert ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        RowLayout {
          id: toastRow
          anchors.centerIn: parent; spacing: 8

          Rectangle {
            width: 8; height: 8; radius: 4; color: Config.recAccent
            SequentialAnimation on opacity {
              running: root.showCastAlert; loops: Animation.Infinite
              NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
          }

          Text {
            text: "Recording in progress"
            color: Config.textColor; font.pixelSize: 13; font.weight: Font.Medium
          }
        }
      }

      //  Floating toolbar 
      Rectangle {
        id: toolbar
        visible: !root.showCastAlert
        clip: true

        readonly property real idleW: mainRow.implicitWidth + 24
        readonly property real idleH: 56

        x:      root.isTransitioningToCast ? parent.width - 6 - 12 : (parent.width - idleW) / 2
        y:      parent.height - height - 40
        width:  root.isTransitioningToCast ? 6    : idleW
        height: root.isTransitioningToCast ? 44   : idleH
        radius: root.isTransitioningToCast ? 3    : idleH / 2

        color:        root.pillBg
        border.color: root.isTransitioningToCast ? Config.recAccent : Config.borderColor
        border.width: 1

        Behavior on x      { enabled: root.isLoaded; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
        Behavior on width  { enabled: root.isLoaded; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
        Behavior on height { enabled: root.isLoaded; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
        Behavior on radius { enabled: root.isLoaded; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }

        MouseArea { anchors.fill: parent }

        RowLayout {
          id: mainRow
          anchors.centerIn: parent; spacing: 8
          opacity: root.isTransitioningToCast ? 0.0 : 1.0
          Behavior on opacity { enabled: root.isLoaded; NumberAnimation { duration: 250 } }

          IconButton { iconName: "camera"; isActive: root.isShot;  activeAccent: Config.ssAccent;  onClicked: root.isShot = true }
          IconButton { iconName: "video";  isActive: !root.isShot; activeAccent: Config.recAccent; onClicked: root.isShot = false }

          VDivider {}

          IconButton { iconName: "crop";           isActive: root.captureMode === "region"; onClicked: root.captureMode = "region" }
          IconButton { iconName: "app-window";     isActive: root.captureMode === "window"; isEnabled: root.isShot; onClicked: root.captureMode = "window" }
          IconButton { iconName: "device-desktop"; isActive: root.captureMode === "screen"; onClicked: root.captureMode = "screen" }

          VDivider {}

          IconButton {
            iconName: root.isShot ? (root.optPointer  ? "pointer"    : "pointer-off")
                                  : (root.optMic       ? "microphone" : "microphone-off")
            isActive: root.isShot ? root.optPointer : root.optMic
            onClicked: root.isShot ? (root.optPointer  = !root.optPointer)
                                   : (root.optMic      = !root.optMic)
          }
          IconButton {
            iconName: root.isShot ? (root.optAnnotate ? "pencil"  : "pencil-off")
                                  : (root.optAudio     ? "volume"  : "volume-3")
            isActive: root.isShot ? root.optAnnotate : root.optAudio
            onClicked: root.isShot ? (root.optAnnotate = !root.optAnnotate)
                                   : (root.optAudio    = !root.optAudio)
          }

          VDivider {}

          IconButton {
            isPrimary: true
            iconName: root.captureMode === "region" && !root.isRegionSelected ? "crop"
                    : root.isShot ? "camera-up" : "player-record"
            onClicked: root.executeAction()
          }
        }

        // Region badge — floats above toolbar when a region is selected
        Rectangle {
          visible: root.captureMode === "region" && root.isRegionSelected
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.top; anchors.bottomMargin: 8
          width: regionBadgeRow.implicitWidth + 20; height: 28; radius: 14
          color: root.pillBg
          border.color: Config.borderColor; border.width: 1

          RowLayout {
            id: regionBadgeRow
            anchors.centerIn: parent; spacing: 0

            // Dimensions
            Text {
              text: root.selW + " × " + root.selH
              font.pixelSize: 11; font.weight: Font.DemiBold
              color: root.accent
              leftPadding: 4
            }

            // Position hint
            Text {
              text: "  @" + root.regionSelX + "," + root.regionSelY
              font.pixelSize: 10; font.weight: Font.Normal
              color: Config.textMuted
            }

            // Separator
            Rectangle {
              width: 1; height: 14
              color: Config.borderColor
              Layout.leftMargin: 8; Layout.rightMargin: 4
            }

            // Re-select button
            Rectangle {
              width: 52; height: 20; radius: 10
              color: reselHover.containsMouse
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                : "transparent"
              border.color: reselHover.containsMouse ? root.accent : "transparent"
              border.width: 1
              Layout.rightMargin: 2

              RowLayout {
                anchors.centerIn: parent; spacing: 4
                Icon { name: "restore"; color: reselHover.containsMouse ? root.accent : Config.textMuted; size: 11 }
                Text {
                  text: "Shift+R"
                  font.pixelSize: 9
                  color: reselHover.containsMouse ? root.accent : Config.textMuted
                }
              }

              MouseArea {
                id: reselHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reEditRegion()
              }
            }
          }
        }
      }
    }
  }
}
