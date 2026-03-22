#!/usr/bin/env python3
"""
Capture a specific Wayland window via xdg-desktop-portal-wlr and GStreamer.
Requires a custom simple chooser script to bypass the UI.
"""

import contextlib
import os
import sys

import gi
gi.require_version('GLib', '2.0')
gi.require_version('Gio', '2.0')
gi.require_version('Gst', '1.0')
from gi.repository import GLib, Gio, Gst  # noqa: E402

PORTAL_BUS_NAME = "org.freedesktop.portal.Desktop"
PORTAL_OBJ_PATH = "/org/freedesktop/portal/desktop"
SCREENCAST_IFACE = "org.freedesktop.portal.ScreenCast"
REQUEST_IFACE = "org.freedesktop.portal.Request"


def portal_request(bus, method, params_variant, expected_key=None):
    """Make a D-Bus portal request and wait for the specific Response signal."""
    loop = GLib.MainLoop()
    result_data = {}
    req_path = None

    def on_response(connection, sender, obj_path, interface, signal, params, user_data):
        nonlocal req_path
        if req_path and obj_path != req_path:
            return  # Ignore signals meant for other concurrent portal requests

        response_code, results = params.unpack()
        if response_code != 0:
            print(f"ERROR: Portal returned code {response_code} for {method}", file=sys.stderr)
        else:
            result_data.update(results)
        loop.quit()

    sub_id = bus.signal_subscribe(
        PORTAL_BUS_NAME, REQUEST_IFACE, "Response",
        None, None, Gio.DBusSignalFlags.NONE, on_response, None
    )

    try:
        req_path = bus.call_sync(
            PORTAL_BUS_NAME, PORTAL_OBJ_PATH, SCREENCAST_IFACE,
            method, params_variant, None, Gio.DBusCallFlags.NONE, -1, None
        ).unpack()[0]
        loop.run()
    finally:
        bus.signal_unsubscribe(sub_id)

    if expected_key and expected_key not in result_data:
        raise RuntimeError(f"Missing expected key '{expected_key}' in response.")

    return result_data


def capture_frame(node_id, output_file="captured_window.jpg", timeout_sec=10):
    """Extract a single frame from the PipeWire node using GStreamer."""
    pipeline_str = (
        f"pipewiresrc path={node_id} num-buffers=1 ! "
        f"videoconvert ! jpegenc ! filesink location={output_file}"
    )
    pipeline = Gst.parse_launch(pipeline_str)
    pipeline.set_state(Gst.State.PLAYING)

    gst_bus = pipeline.get_bus()
    msg = gst_bus.timed_pop_filtered(
        timeout_sec * Gst.SECOND,
        Gst.MessageType.EOS | Gst.MessageType.ERROR
    )

    success = False
    if msg:
        if msg.type == Gst.MessageType.ERROR:
            err, _ = msg.parse_error()
            print(f"ERROR: GStreamer pipeline failed: {err.message}", file=sys.stderr)
        elif msg.type == Gst.MessageType.EOS:
            success = True
    else:
        print("\nERROR: Capture timed out. Compositor likely culled the window.", file=sys.stderr)
        print("Workaround: Try making the window active/visible first.", file=sys.stderr)

    pipeline.set_state(Gst.State.NULL)
    return success


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <window_id>", file=sys.stderr)
        sys.exit(1)

    target_window_id = sys.argv[1]
    tmp_file = "/tmp/xdpw-target-window-id"

    # Write target ID for the external bash chooser
    with open(tmp_file, "w") as f:
        f.write(target_window_id)

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    Gst.init(None)

    session_path = None

    try:
        # 1. Create Session
        res = portal_request(
            bus, "CreateSession",
            GLib.Variant("(a{sv})", ({"session_handle_token": GLib.Variant("s", "cap_session")},)),
            "session_handle"
        )
        session_path = res["session_handle"]

        # 2. Select Sources
        portal_request(
            bus, "SelectSources",
            GLib.Variant("(oa{sv})", (session_path, {
                "types": GLib.Variant("u", 2),  # 2 = Window
                "multiple": GLib.Variant("b", False)
            }))
        )

        # Clean up temp file instantly to prevent race conditions
        with contextlib.suppress(FileNotFoundError):
            os.remove(tmp_file)

        # 3. Start Session
        res = portal_request(
            bus, "Start",
            GLib.Variant("(osa{sv})", (session_path, "", {})),
            "streams"
        )
        node_id = res["streams"][0][0]

        # 4. Extract Frame
        if capture_frame(node_id):
            print("✓ Frame captured successfully: captured_window.jpg")
            sys.exit(0)
        else:
            sys.exit(1)

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    finally:
        # 5. Always cleanup the D-Bus session
        if session_path:
            with contextlib.suppress(GLib.Error):
                bus.call_sync(
                    PORTAL_BUS_NAME, session_path,
                    "org.freedesktop.portal.Session", "Close",
                    None, None, Gio.DBusCallFlags.NONE, -1, None
                )


if __name__ == "__main__":
    main()
