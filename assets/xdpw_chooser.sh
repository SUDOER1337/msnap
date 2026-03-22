#!/bin/sh
# xdpw_chooser.sh

GUI_PATH="@GUI_PATH@"
WINDOW_PICKER="$GUI_PATH/WindowPicker.qml"
TMP_FILE="/tmp/xdpw-target-window-id"

if [ -f "$TMP_FILE" ]; then
    TARGET_ID=$(cat "$TMP_FILE")
    rm -f "$TMP_FILE"
    if [ -n "$TARGET_ID" ]; then
        echo "Window: $TARGET_ID"
    fi
    exit 0
fi

rm -f "$TMP_FILE"

quickshell -p "$WINDOW_PICKER" >/dev/null 2>&1 &
QS_PID=$!

while [ ! -f "$TMP_FILE" ]; do
    if ! kill -0 $QS_PID 2>/dev/null; then
        exit 0
    fi
    sleep 0.2
done

TARGET_ID=$(cat "$TMP_FILE")
rm -f "$TMP_FILE"

if [ -n "$TARGET_ID" ]; then
    echo "Window: $TARGET_ID"
fi
