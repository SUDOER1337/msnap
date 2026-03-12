#!/bin/sh
set -e

REPO="https://github.com/atheeq-rhxn/msnap.git"
TMP="$(mktemp -d)"

XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

BIN_DIR="$XDG_BIN_HOME"
CONFIG_DIR="$XDG_CONFIG_HOME/msnap"

echo "Cloning msnap…"
git clone --depth=1 "$REPO" "$TMP"

echo "Installing binary to $BIN_DIR…"
mkdir -p "$BIN_DIR"
chmod +x "$TMP/cli/msnap"
cp "$TMP/cli/msnap" "$BIN_DIR/msnap"

echo "Installing configs to $CONFIG_DIR…"
mkdir -p "$CONFIG_DIR"
cp -n "$TMP/cli/msnap.conf" "$CONFIG_DIR/"

echo "Installing gui to $CONFIG_DIR/gui…"
mkdir -p "$CONFIG_DIR/gui/icons"
cp "$TMP/gui/shell.qml" "$CONFIG_DIR/gui/"
cp "$TMP/gui/RegionSelector.qml" "$CONFIG_DIR/gui/"
cp "$TMP/gui/Icon.qml" "$CONFIG_DIR/gui/"
cp "$TMP/gui/Config.qml" "$CONFIG_DIR/gui/"
cp -n "$TMP/gui/gui.conf" "$CONFIG_DIR/"
cp "$TMP/gui/icons/"*.svg "$CONFIG_DIR/gui/icons/"

echo "Installing desktop entry and icon…"
mkdir -p "$XDG_DATA_HOME/applications"
sed "s|@GUI_PATH@|$CONFIG_DIR/gui|g" "$TMP/assets/msnap.desktop.in" \
    > "$XDG_DATA_HOME/applications/msnap.desktop"
mkdir -p "$XDG_DATA_HOME/icons/hicolor/scalable/apps"
cp "$TMP/assets/icons/msnap.svg" "$XDG_DATA_HOME/icons/hicolor/scalable/apps/"

echo "Cleaning up…"
rm -rf "$TMP"

echo
echo "Done!"
echo "✔ msnap (CLI)    → $BIN_DIR"
echo "✔ msnap.conf     → $CONFIG_DIR"
echo "✔ gui            → $CONFIG_DIR/gui"
echo "✔ desktop entry  → $XDG_DATA_HOME/applications"
echo "✔ icon           → $XDG_DATA_HOME/icons/hicolor/scalable/apps"
echo
echo "Make sure $BIN_DIR is in your PATH:"
echo "    export PATH=\"$BIN_DIR:\$PATH\""
echo
echo "Usage:"
echo "    msnap shot [OPTIONS]      # Take a screenshot"
echo "    msnap cast [OPTIONS]      # Record screen"
echo
echo "For detailed help:"
echo "    msnap --help"
echo "    msnap shot --help"
echo "    msnap cast --help"
