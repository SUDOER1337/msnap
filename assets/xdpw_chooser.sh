#!/bin/sh
# xdpw_chooser.sh

# Read the target identifier from a temporary file
TARGET_ID=$(cat /tmp/xdpw-target-window-id)

# Return the exact string xdg-desktop-portal-wlr expects
echo "Window: $TARGET_ID"
