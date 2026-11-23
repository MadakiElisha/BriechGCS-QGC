"""Frames from a live camera.

    --camera 0                 a USB camera, by index (V4L2 on Linux)
    --camera csi:0             a Jetson CSI camera (sensor-id 0), such as the IMX477, through nvarguscamerasrc
    --camera rtsp://...        an IP camera's stream
    --camera gst:<pipeline>    any GStreamer pipeline that ends in appsink

A live camera is read as it comes, newest frame only: when the detector is
slower than the camera, frames are dropped, never queued, so detections stay
current. A CSI camera and a raw pipeline need an OpenCV built with GStreamer.
JetPack's own OpenCV (``python3-opencv``) has it; the pip wheel does not, so on
a Jetson make the virtualenv with ``--system-site-packages`` and leave the
wheel out.

The picture must be the size the camera's control points were measured on,
or every position the tower reports is wrong. ``camera.capture`` in the
camera config states that size, and a camera whose frames differ is refused.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlsplit

import cv2
import numpy as np


class CameraError(RuntimeError):
    """The camera cannot be opened, or gives pictures this config cannot use."""


@dataclass(frozen=True)
class Capture:
    """The picture size and rate asked of the camera (``camera.capture`` in the config)."""

    width: int | None = None
    height: int | None = None
    fps: float | None = None

    @classmethod
    def from_config(cls, data: dict | None) -> Capture:
        data = data or {}
        width, height, fps = data.get("width"), data.get("height"), data.get("fps")
        for name, value in (("width", width), ("height", height), ("fps", fps)):
            if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0):
                raise CameraError(f"camera.capture.{name} must be a positive number, not {value!r}")
        return cls(width=int(width) if width else None, height=int(height) if height else None,
                   fps=float(fps) if fps else None)

    @property
    def sized(self) -> bool:
        return bool(self.width and self.height)


def csi_pipeline(sensor_id: int, capture: Capture) -> str:
    """The GStreamer pipeline for a Jetson CSI camera, giving BGR frames to OpenCV, newest only."""
    width, height = capture.width or 1920, capture.height or 1080
    fps = max(1, round(capture.fps or 30))
    return (f"nvarguscamerasrc sensor-id={sensor_id} ! "
            f"video/x-raw(memory:NVMM),width={width},height={height},framerate={fps}/1 ! "
            "nvvidconv ! video/x-raw,format=BGRx ! videoconvert ! video/x-raw,format=BGR ! "
            "appsink drop=true max-buffers=1 sync=false")


def open_target(spec: str, capture: Capture) -> tuple[int | str, int]:
    """What to give cv2.VideoCapture for a ``--camera`` value: (target, backend)."""
    spec = spec.strip()
    if spec.isdigit():
        return int(spec), cv2.CAP_ANY
    if spec.startswith("csi:"):
        sensor = spec[len("csi:"):]
        if not sensor.isdigit():
            raise CameraError(f"bad CSI camera '{spec}': use csi:0, csi:1, ...")
        return csi_pipeline(int(sensor), capture), cv2.CAP_GSTREAMER
    if spec.startswith("gst:"):
        pipeline = spec[len("gst:"):].strip()
        if "appsink" not in pipeline:
            raise CameraError("a GStreamer pipeline for --camera must end in appsink")
        return pipeline, cv2.CAP_GSTREAMER
    if spec.startswith(("rtsp://", "rtsps://")):
        return spec, cv2.CAP_FFMPEG
    raise CameraError(f"unknown camera '{describe(spec)}': use an index (0), csi:<n>, rtsp://... or gst:<pipeline>")


def describe(spec: str) -> str:
    """A name for logs. Never the whole URL: an RTSP address can carry a login."""
    spec = spec.strip()
    if spec.isdigit():
        return f"camera {spec}"
    if spec.startswith("csi:"):
        return f"CSI camera {spec[len('csi:'):]}"
    if spec.startswith("gst:"):
        return "GStreamer pipeline"
    if spec.startswith(("rtsp://", "rtsps://")):
        try:
            host = urlsplit(spec).hostname
        except ValueError:
            host = None
        return f"RTSP stream at {host or 'an unreadable address'}"
    return "an unrecognised camera"


def check_size(frame: np.ndarray, capture: Capture, name: str) -> None:
    """Refuse pictures of another size than the one the control points were measured on."""
    height, width = frame.shape[:2]
    if capture.sized and (width, height) != (capture.width, capture.height):
        raise CameraError(f"{name} gives {width}x{height} pictures, but the control points are for "
                          f"{capture.width}x{capture.height}: fix camera.capture or the camera's mode")


class Camera:
    """A live camera with the same reading calls as ``Video``."""

    live = True

    def __init__(self, spec: str, capture: Capture):
        target, backend = open_target(spec, capture)
        self.name = describe(spec)
        self._capture = capture
        self._checked = False
        self._cap = cv2.VideoCapture(target, backend)
        if not self._cap.isOpened():
            hint = ""
            if backend == cv2.CAP_GSTREAMER and re.search(r"GStreamer:\s*NO", cv2.getBuildInformation()):
                hint = " (this OpenCV has no GStreamer: use JetPack's python3-opencv)"
            raise CameraError(f"cannot open {self.name}{hint}")
        if isinstance(target, int):
            # A USB camera: ask for the configured mode, and keep only the newest frame.
            if capture.width:
                self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, capture.width)
            if capture.height:
                self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, capture.height)
            if capture.fps:
                self._cap.set(cv2.CAP_PROP_FPS, capture.fps)
            self._cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        reported = self._cap.get(cv2.CAP_PROP_FPS)
        self.fps = capture.fps or (reported if 1.0 <= reported <= 240.0 else 30.0)
        self.backend = self._cap.getBackendName()

    def read(self) -> np.ndarray | None:
        """The newest frame, or None when the camera stops giving pictures."""
        ok, frame = self._cap.read()
        if not ok or frame is None:
            return None
        if not self._checked:
            check_size(frame, self._capture, self.name)
            self._checked = True
        return frame

    def skip(self) -> bool:
        """Nothing to skip: a live camera is always read newest first."""
        return False

    def rewind(self) -> None:
        """A live camera cannot go back."""

    def close(self) -> None:
        self._cap.release()
