import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    signal windowSelected(string identifier, string title, string appId)
    signal cancelled()

    property alias searchText: searchInput.text
    property alias currentIndex: windowList.currentIndex
    property color accentColor: Config.ssAccent

    readonly property bool hasSelection: windowList.currentIndex >= 0 &&
                                         windowList.currentIndex < displayModel.count
    readonly property bool isLoading: internal.isLoading
    readonly property string errorMessage: internal.errorMessage

    function activate() {
        searchInput.text = ""
        internal.errorMessage = ""
        internal.isLoading = true
        internal.sourceModel.clear()
        displayModel.clear()

        if (internal.lswtProcess.running) {
            internal.restartRequested = true
            internal.lswtProcess.running = false
        } else {
            internal.lswtProcess.running = true
        }

        focusTimer.restart()
    }

    function selectCurrent() {
        if (!hasSelection) return
        const item = displayModel.get(windowList.currentIndex)
        root.windowSelected(item.identifier, item.title, item.appId)
    }

    function performSearch() {
        const query = searchInput.text.toLowerCase().trim()
        displayModel.clear()

        for (let i = 0; i < internal.sourceModel.count; i++) {
            const item = internal.sourceModel.get(i)
            const appName = DesktopEntries.byId(item.appId)?.name ?? item.appId
            if (!query ||
                item.title.toLowerCase().includes(query) ||
                appName.toLowerCase().includes(query) ||
                item.appId.toLowerCase().includes(query)) {
                displayModel.append({ identifier: item.identifier, title: item.title, appId: item.appId })
            }
        }

        windowList.currentIndex = displayModel.count > 0 ? 0 : -1
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    QtObject {
        id: internal

        property bool isLoading: false
        property string errorMessage: ""
        property bool restartRequested: false
        property ListModel sourceModel: ListModel {}

        function sanitize(str) {
            if (!str || typeof str !== 'string') return ""
            return String(str).slice(0, 200).replace(/[\x00-\x1F\x7F-\x9F]/g, '')
        }

        property Timer searchDebounce: Timer {
            interval: 150
            onTriggered: root.performSearch()
        }

        property Process lswtProcess: Process {
            command: ["lswt", "-j"]
            running: false

            onStarted: internal.isLoading = true

            onExited: {
                if (internal.restartRequested) {
                    internal.restartRequested = false
                    running = true
                }
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    internal.isLoading = false

                    if (!text?.trim()) {
                        internal.errorMessage = "No window data returned"
                        return
                    }

                    try {
                        const data = JSON.parse(text)

                        if (!Array.isArray(data?.toplevels)) {
                            internal.errorMessage = "Invalid data format"
                            return
                        }

                        internal.sourceModel.clear()

                        let count = 0
                        for (const w of data.toplevels) {
                            if (!w || typeof w !== 'object') continue
                            if (w["app-id"] === "msnap") continue

                            const identifier = internal.sanitize(String(w.identifier ?? ""))
                            if (!identifier) continue

                            internal.sourceModel.append({
                                identifier,
                                title: internal.sanitize(String(w.title ?? "Unknown Window")),
                                appId: internal.sanitize(String(w["app-id"] ?? "unknown"))
                            })
                            count++
                        }

                        if (count === 0) {
                            internal.errorMessage = "No valid windows found"
                            return
                        }

                        internal.errorMessage = ""
                        root.performSearch()

                    } catch (e) {
                        internal.errorMessage = "Failed to parse data"
                        console.error("lswt parse error:", e.toString())
                    }
                }
            }

            stderr: StdioCollector {
                onStreamFinished: if (text?.trim()) console.error("lswt:", text)
            }
        }
    }

    ListModel { id: displayModel }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { internal.searchDebounce.restart() }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Config.surfaceColor.r, Config.surfaceColor.g, Config.surfaceColor.b, 0.98)
        border.color: Config.borderColor
        border.width: 1
        radius: 12
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Search bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: height / 2
                color: Qt.rgba(Config.bgColor.r, Config.bgColor.g, Config.bgColor.b, 0.5)
                border.color: searchInput.activeFocus ? root.accentColor : Config.borderColor
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 10

                    Icon {
                        name: "search"
                        size: 16
                        color: searchInput.activeFocus ? root.accentColor : Config.textMuted
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: Config.textColor
                        font.pixelSize: 14
                        clip: true
                        selectByMouse: true
                        focus: true
                        verticalAlignment: TextInput.AlignVCenter

                        Text {
                            text: "Search windows…"
                            color: Config.textMuted
                            font.pixelSize: 14
                            visible: !searchInput.text && !searchInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        onTextChanged: internal.searchDebounce.restart()

                        Keys.onPressed: function(event) {
                            switch (event.key) {
                            case Qt.Key_Escape:
                                event.accepted = true
                                searchInput.text !== "" ? searchInput.text = "" : root.cancelled()
                                break
                            case Qt.Key_Up:
                                event.accepted = true
                                if (windowList.currentIndex > 0) windowList.currentIndex--
                                break
                            case Qt.Key_Down:
                                event.accepted = true
                                if (windowList.currentIndex < displayModel.count - 1) windowList.currentIndex++
                                break
                            case Qt.Key_Tab:
                            case Qt.Key_Backtab:
                                event.accepted = true
                                const backward = event.modifiers & Qt.ShiftModifier || event.key === Qt.Key_Backtab
                                windowList.currentIndex = backward
                                    ? (windowList.currentIndex > 0 ? windowList.currentIndex - 1 : displayModel.count - 1)
                                    : (windowList.currentIndex < displayModel.count - 1 ? windowList.currentIndex + 1 : 0)
                                break
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                event.accepted = true
                                root.selectCurrent()
                                break
                            }
                        }
                    }

                    Rectangle {
                        width: 22
                        height: 22
                        radius: 11
                        color: Qt.rgba(Config.textMuted.r, Config.textMuted.g, Config.textMuted.b,
                                       clearHover.containsMouse ? 0.25 : 0.12)
                        visible: searchInput.text !== ""

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: Config.textMuted
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: clearHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                        }
                    }
                }
            }

            // Result count
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                visible: !internal.isLoading && internal.errorMessage === "" && internal.sourceModel.count > 0
                spacing: 0

                Text {
                    text: searchInput.text !== ""
                        ? displayModel.count + " of " + internal.sourceModel.count + " windows"
                        : internal.sourceModel.count + " windows"
                    color: Config.textMuted
                    font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "↑↓ to navigate"
                    color: Qt.rgba(Config.textMuted.r, Config.textMuted.g, Config.textMuted.b, 0.55)
                    font.pixelSize: 11
                    visible: displayModel.count > 1
                }
            }

            // Content area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.centerIn: parent
                    text: "Loading windows…"
                    color: Config.textMuted
                    font.pixelSize: 13
                    visible: internal.isLoading
                }

                Text {
                    anchors.centerIn: parent
                    text: internal.errorMessage
                    color: Config.textMuted
                    font.pixelSize: 13
                    visible: !internal.isLoading && internal.errorMessage !== ""
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: !internal.isLoading && internal.errorMessage === "" &&
                             displayModel.count === 0 && internal.sourceModel.count > 0

                    Icon {
                        name: "ghost"
                        size: 32
                        color: Config.textMuted
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "No matching windows"
                        color: Config.textMuted
                        font.pixelSize: 13
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No other windows open"
                    color: Config.textMuted
                    font.pixelSize: 13
                    visible: !internal.isLoading && internal.errorMessage === "" &&
                             internal.sourceModel.count === 0
                }

                ListView {
                    id: windowList
                    anchors.fill: parent
                    anchors.rightMargin: 8
                    visible: !internal.isLoading && internal.errorMessage === "" && displayModel.count > 0
                    model: displayModel
                    spacing: 2
                    clip: true
                    cacheBuffer: 200
                    highlightMoveDuration: 0

                    delegate: MouseArea {
                        id: delegateArea
                        width: ListView.view.width
                        height: 56
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        readonly property var desktopEntry: {
                            void DesktopEntries.applications
                            return DesktopEntries.byId(model.appId)
                        }
                        readonly property bool isSelected: windowList.currentIndex === index
                        readonly property color accentFill: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                        readonly property color accentHover: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.06)

                        onClicked: { windowList.currentIndex = index; root.selectCurrent() }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: delegateArea.isSelected ? delegateArea.accentFill
                                 : delegateArea.containsMouse ? delegateArea.accentHover
                                 : "transparent"
                            border.width: delegateArea.isSelected ? 1 : 0
                            border.color: root.accentColor

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Item {
                                    width: 28
                                    height: 28
                                    Layout.alignment: Qt.AlignVCenter

                                    Image {
                                        id: appIconImage
                                        anchors.fill: parent
                                        source: delegateArea.desktopEntry?.icon
                                            ? "image://icon/" + delegateArea.desktopEntry.icon : ""
                                        visible: source !== "" && status === Image.Ready
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }

                                    Icon {
                                        anchors.fill: parent
                                        name: "app-window"
                                        size: 22
                                        color: delegateArea.isSelected ? root.accentColor : Config.textMuted
                                        visible: !appIconImage.visible
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: delegateArea.desktopEntry?.name ?? model.appId
                                        color: delegateArea.isSelected ? root.accentColor : Config.textColor
                                        font.pixelSize: 13
                                        font.weight: delegateArea.isSelected ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: model.title
                                        color: Config.textMuted
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Text {
                                    text: "↵"
                                    color: root.accentColor
                                    font.pixelSize: 13
                                    visible: delegateArea.isSelected
                                    Layout.alignment: Qt.AlignVCenter
                                    opacity: 0.7
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: scrollIndicator
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    radius: 2
                    color: Qt.rgba(Config.borderColor.r, Config.borderColor.g, Config.borderColor.b, 0.4)
                    visible: windowList.visible && windowList.visibleArea.heightRatio < 1.0

                    Rectangle {
                        width: parent.width
                        radius: 2
                        color: Config.textMuted
                        y: windowList.visibleArea.yPosition * scrollIndicator.height
                        height: windowList.visibleArea.heightRatio * scrollIndicator.height
                    }
                }
            }

            // Footer
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Config.borderColor
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 2

                Text {
                    text: "Esc · cancel"
                    color: Qt.rgba(Config.textMuted.r, Config.textMuted.g, Config.textMuted.b, 0.6)
                    font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "↵ · capture"
                    color: Qt.rgba(Config.textMuted.r, Config.textMuted.g, Config.textMuted.b, 0.6)
                    font.pixelSize: 11
                }
            }
        }
    }
}
