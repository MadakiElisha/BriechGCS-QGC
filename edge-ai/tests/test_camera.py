"""The live camera input: what each --camera value opens, the size check, and the refusals."""

import subprocess
import sys

import cv2
import numpy as np
import pytest

from pipeline import camera as cam
from pipeline.camera import Camera, CameraError, Capture, check_size, describe, open_target

from conftest import EDGE_DIR

HD = Capture(width=1920, height=1080, fps=30)


def test_usb_index():
    assert open_target("0", HD) == (0, cv2.CAP_ANY)
    assert open_target(" 2 ", HD) == (2, cv2.CAP_ANY)


def test_csi_pipeline_uses_the_capture_size_and_keeps_only_the_newest_frame():
    target, backend = open_target("csi:1", Capture(width=1280, height=720, fps=60))
    assert backend == cv2.CAP_GSTREAMER
    assert "nvarguscamerasrc sensor-id=1" in target
    assert "width=1280,height=720,framerate=60/1" in target
    assert target.endswith("appsink drop=true max-buffers=1 sync=false")


def test_rtsp_and_raw_pipeline():
    assert open_target("rtsp://cam.lan/stream", HD) == ("rtsp://cam.lan/stream", cv2.CAP_FFMPEG)
    assert open_target("gst:videotestsrc ! videoconvert ! appsink", HD) == \
        ("videotestsrc ! videoconvert ! appsink", cv2.CAP_GSTREAMER)


@pytest.mark.parametrize("spec", ["csi:x", "gst:videotestsrc ! fakesink", "/dev/video0", "http://cam/"])
def test_refused(spec):
    with pytest.raises(CameraError):
        open_target(spec, HD)


def test_logs_never_carry_a_login_or_path():
    name = describe("rtsp://admin:s3cret@10.0.0.5:554/live/main")
    assert name == "RTSP stream at 10.0.0.5"
    with pytest.raises(CameraError) as e:
        open_target("ftp://admin:s3cret@cam/x", HD)
    assert "s3cret" not in str(e.value)


def test_capture_from_config():
    assert Capture.from_config(None) == Capture()
    assert Capture.from_config({"width": 1920, "height": 1080}).sized
    assert not Capture.from_config({"width": 1920}).sized
    for bad in ({"width": -1}, {"height": "1080"}, {"fps": True}, {"fps": 0}):
        with pytest.raises(CameraError):
            Capture.from_config(bad)


def test_size_check():
    frame = np.zeros((1080, 1920, 3), np.uint8)
    check_size(frame, HD, "camera 0")
    check_size(frame, Capture(), "camera 0")          # no size given: nothing to compare
    with pytest.raises(CameraError, match="1920x1080 pictures, but the control points are for 1280x720"):
        check_size(frame, Capture(width=1280, height=720), "camera 0")


class FakeCapture:
    """Stands in for cv2.VideoCapture: gives the frames it was made with, then nothing."""

    def __init__(self, frames, opened=True):
        self.frames, self.opened, self.props, self.released = list(frames), opened, {}, False

    def isOpened(self):
        return self.opened

    def set(self, prop, value):
        self.props[prop] = value
        return True

    def get(self, prop):
        return 0.0                                  # many cameras report no rate

    def getBackendName(self):
        return "FAKE"

    def read(self):
        return (True, self.frames.pop(0)) if self.frames else (False, None)

    def release(self):
        self.released = True


def fake(monkeypatch, frames, opened=True):
    made = FakeCapture(frames, opened)
    monkeypatch.setattr(cam.cv2, "VideoCapture", lambda target, backend: made)
    return made


def test_usb_camera_is_asked_for_the_configured_mode(monkeypatch):
    made = fake(monkeypatch, [np.zeros((1080, 1920, 3), np.uint8)])
    camera = Camera("0", HD)
    assert made.props[cv2.CAP_PROP_FRAME_WIDTH] == 1920
    assert made.props[cv2.CAP_PROP_FRAME_HEIGHT] == 1080
    assert made.props[cv2.CAP_PROP_BUFFERSIZE] == 1
    assert camera.fps == 30
    assert camera.read().shape == (1080, 1920, 3)
    assert camera.read() is None                    # stopped giving pictures
    assert camera.skip() is False
    camera.close()
    assert made.released


def test_unreported_rate_falls_back_to_30(monkeypatch):
    fake(monkeypatch, [])
    assert Camera("0", Capture(width=640, height=480)).fps == 30.0


def test_wrong_size_is_refused_on_the_first_frame(monkeypatch):
    fake(monkeypatch, [np.zeros((720, 1280, 3), np.uint8)])
    camera = Camera("0", HD)
    with pytest.raises(CameraError, match="1280x720"):
        camera.read()


def test_camera_that_does_not_open(monkeypatch):
    fake(monkeypatch, [], opened=False)
    with pytest.raises(CameraError, match="cannot open camera 3"):
        Camera("3", HD)


def run(*args):
    return subprocess.run([sys.executable, "-m", "pipeline.run", *args], cwd=EDGE_DIR,
                          capture_output=True, text=True, timeout=60)


def test_run_refuses_loop_with_a_camera():
    done = run("--camera", "0", "--loop")
    assert done.returncode == 2 and "--loop is for a video file" in done.stderr


def test_run_refuses_a_camera_without_a_capture_size():
    done = run("--camera", "0", "--config", "config/test-video.yaml")
    assert done.returncode == 1 and "needs camera.capture.width and height" in done.stderr


def test_run_refuses_the_template_until_points_are_measured():
    done = run("--camera", "csi:0", "--config", "config/tower-camera.example.yaml")
    assert done.returncode == 1 and "at least 4 control points" in done.stderr
