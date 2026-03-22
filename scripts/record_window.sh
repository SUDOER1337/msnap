#!/usr/bin/env bash

if [ -z "$1" ]; then
    echo "Usage: $0 <lswt_window_identifier>"
    exit 1
fi

TARGET_ID="$1"
OUTPUT_FILE="hidden_capture_$(date +%s).mp4"

# 1. Feed the target to our portal bypass
echo "$TARGET_ID" > /tmp/xdpw-target-window-id

echo "Starting GPU Screen Recorder silently for window: $TARGET_ID"

gpu-screen-recorder -w portal -f 60 -a "" -o "$OUTPUT_FILE"
