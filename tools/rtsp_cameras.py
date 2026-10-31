#!/usr/bin/env python3
"""Simulated security cameras: serves N RTSP streams (rtsp://<host>:8554/camK) of one H.264 file,
played at real-time speed, using Ubuntu's packaged GStreamer RTSP server.
Install: sudo apt install python3-gi gir1.2-gst-rtsp-server-1.0 gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
Usage:   python3 rtsp_cameras.py <video.mp4> [N]"""
import sys, gi
gi.require_version("Gst", "1.0"); gi.require_version("GstRtspServer", "1.0")
from gi.repository import Gst, GstRtspServer, GLib
Gst.init(None)
video, n = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 30
server = GstRtspServer.RTSPServer(); server.set_service("8554")
mounts = server.get_mount_points()
for k in range(1, n + 1):
    f = GstRtspServer.RTSPMediaFactory()
    f.set_launch(f"( filesrc location={video} ! qtdemux ! h264parse config-interval=-1 ! rtph264pay name=pay0 pt=96 )")
    f.set_shared(True)
    mounts.add_factory(f"/cam{k}", f)
server.attach(None)
print(f"serving {n} cameras on rtsp://0.0.0.0:8554/cam1..cam{n}", flush=True)
GLib.MainLoop().run()
