"""Frames from a video file.

OpenCV reads the file when its build can decode it. Some builds cannot (the
macOS Intel wheel has no FFmpeg, so no AVI), and then the ``ffmpeg`` command
is used instead, when it is installed. Both give BGR frames.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import cv2
import numpy as np


class Video:
    def __init__(self, path: Path):
        self.path = Path(path)
        self._proc: subprocess.Popen | None = None
        self._cap = cv2.VideoCapture(str(self.path))
        if self._cap.isOpened():
            self.fps = self._cap.get(cv2.CAP_PROP_FPS) or 10.0
            self.backend = "opencv"
            return
        self._cap = None
        if not (shutil.which("ffmpeg") and shutil.which("ffprobe")):
            raise SystemExit(f"cannot open {self.path}: this OpenCV build cannot decode it and ffmpeg is not installed")
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
             "stream=width,height,avg_frame_rate", "-of", "json", str(self.path)],
            capture_output=True, text=True, check=False)
        try:
            stream = json.loads(probe.stdout)["streams"][0]
            self._width, self._height = int(stream["width"]), int(stream["height"])
            num, _, den = stream["avg_frame_rate"].partition("/")
            self.fps = float(num) / float(den or 1) or 10.0
        except (ValueError, KeyError, IndexError, ZeroDivisionError):
            raise SystemExit(f"cannot open {self.path}: {probe.stderr.strip() or 'no video stream'}") from None
        self.backend = "ffmpeg"
        self._start()

    def _start(self) -> None:
        self._proc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-nostdin", "-i", str(self.path), "-f", "rawvideo", "-pix_fmt", "bgr24", "-"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def read(self) -> np.ndarray | None:
        """The next frame, or None at the end."""
        if self._cap is not None:
            ok, frame = self._cap.read()
            return frame if ok else None
        size = self._width * self._height * 3
        raw = self._proc.stdout.read(size)
        if len(raw) < size:
            return None
        return np.frombuffer(raw, np.uint8).reshape(self._height, self._width, 3)

    def skip(self) -> bool:
        """Pass over one frame without using it. False at the end."""
        if self._cap is not None:
            return self._cap.grab()
        return self.read() is not None

    def rewind(self) -> None:
        if self._cap is not None:
            self._cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            return
        self.close()
        self._start()

    def close(self) -> None:
        if self._cap is not None:
            self._cap.release()
        if self._proc is not None:
            self._proc.kill()
            self._proc.wait()
            self._proc = None
