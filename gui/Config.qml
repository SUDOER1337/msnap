pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  // Color scheme
  property color ssAccent: "#7aa2f7"
  property color recAccent: "#f7768e"
  property color bgColor: "#13141d"
  property color surfaceColor: "#1a1b26"
  property color textColor: "#c0caf5"
  property color textMuted: "#565f89"
  property color borderColor: "#2a2d3e"
  property color overlayColor: "#000000"
  property real overlayAlpha: 0.5
  property color handleColor: "#ffffff"
  property color dimLabelBg: "#000000"
  property real dimLabelAlpha: 0.75
  property color instructionColor: "#ffffff"
  property real instructionAlpha: 0.65

  // Behavior
  property bool quickCapture: false

  // Paths - centralized configuration
  readonly property string homePath: Quickshell.env("HOME")

  readonly property string xdgConfigHome: {
    var val = Quickshell.env("XDG_CONFIG_HOME");
    return (val !== "" && val !== null) ? val : (homePath + "/.config");
  }

  readonly property string xdgConfigDirs: {
    var val = Quickshell.env("XDG_CONFIG_DIRS");
    return (val !== "" && val !== null) ? val : "/etc/xdg";
  }

  readonly property string xdgBinHome: {
    var val = Quickshell.env("XDG_BIN_HOME");
    return (val !== "" && val !== null) ? val : (homePath + "/.local/bin");
  }

  readonly property var configSearchDirs: {
    var dirs = xdgConfigDirs.split(":").filter(function(d) { return d.length > 0; });
    return [xdgConfigHome].concat(dirs);
  }

  property int _configSearchIndex: 0
  property string configPath: configSearchDirs[0] + "/msnap/gui.conf"

  // Find msnap binary: user install first, then system
  readonly property string msnapPath: {
    // User install
    if (FileUtils.exists(xdgBinHome + "/msnap"))
        return xdgBinHome + "/msnap";
    
    // System install
    if (FileUtils.exists("/usr/bin/msnap"))
        return "/usr/bin/msnap";
    
    // Fallback to user install path
    return xdgBinHome + "/msnap";
  }
  
  readonly property string pidFilePath: "/tmp/msnap-cast.pid"

  // UI Constants
  readonly property int panelWidth: 276
  readonly property int panelBottomMargin: 68
  readonly property int buttonHeight: 64
  readonly property int toggleButtonSize: 36
  readonly property int defaultSpacing: 6
  readonly property int defaultBorderRadius: 8

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    onTextChanged: {
      root._configSearchIndex = 0
      root.loadConfig(text())
    }
    onLoadFailed: {
      root._configSearchIndex++;
      if (root._configSearchIndex < root.configSearchDirs.length) {
        root.configPath = root.configSearchDirs[root._configSearchIndex] + "/msnap/gui.conf";
      } else {
        root._configSearchIndex = 0;
        root.configPath = root.configSearchDirs[0] + "/msnap/gui.conf";
        reloadTimer.start();
      }
    }
  }

  Timer {
    id: reloadTimer
    interval: 1000
    repeat: false
    onTriggered: configFile.reload()
  }

  function loadConfig(data) {
    if (!data)
      return;

    try {
      const lines = data.split('\n');
      const updates = {};

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#'))
          continue;

        const eqIndex = trimmed.indexOf('=');
        if (eqIndex === -1)
          continue;

        const key = trimmed.substring(0, eqIndex).trim();
        const value = trimmed.substring(eqIndex + 1).trim();

        // Convert snake_case to camelCase
        const camelKey = key.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());

        if (camelKey in root) {
          if (value === "true") updates[camelKey] = true;
          else if (value === "false") updates[camelKey] = false;
          else updates[camelKey] = value;
        }
      }

      // Batch update to minimize binding notifications
      for (const [key, value] of Object.entries(updates)) {
        root[key] = value;
      }
    } catch (error) {
      console.error("Config parsing error:", error);
      console.error("Falling back to default configuration");
    }
  }
}
