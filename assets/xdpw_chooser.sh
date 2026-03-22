#!/bin/sh
# xdpw_chooser.sh

GUI_PATH="@GUI_PATH@"
WINDOW_PICKER="$GUI_PATH/WindowPicker.qml"

rm -f /tmp/xdpw-target-window-id

quickshell -p "$WINDOW_PICKER" >/dev/null 2>&1 &
QS_PID=$!

while [ ! -f /tmp/xdpw-target-window-id ]; do
    if ! kill -0 $QS_PID 2>/dev/null; then
        exit 0
    fi
    sleep 0.2
done

TARGET_ID=$(cat /tmp/xdpw-target-window-id)
rm -f /tmp/xdpw-target-window-id

if [ -n "$TARGET_ID" ]; then
    echo "Window: $TARGET_ID"
fi
