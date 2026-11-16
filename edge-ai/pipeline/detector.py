"""Detector: a frame in, boxes out (class, confidence, pixels).

One backend today: YOLOX from an ONNX file, run with OpenCV's DNN module, so
the only dependencies are numpy and OpenCV. The model is described by a config
in ``models/`` (where it comes from, its checksum, its licence, its classes);
the weights themselves are downloaded, never committed.

On a Jetson this stage is replaced by a TensorRT engine with the same
``detect`` method (handoff section 9); nothing after it changes.
"""

from __future__ import annotations

import hashlib
import logging
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
import yaml

log = logging.getLogger(__name__)


@dataclass
class Box:
    cls: str                # "person" or "vehicle"
    confidence: float
    x: float                # pixels, top-left corner
    y: float
    w: float
    h: float


@dataclass
class ModelConfig:
    version: str
    url: str
    sha256: str
    licence: str
    input_size: int
    classes: dict[int, str]     # the model's class index -> our class
    path: Path                  # where the weights are (or will be) on this machine

    @classmethod
    def load(cls, config_file: Path, weights_dir: Path) -> ModelConfig:
        raw = yaml.safe_load(Path(config_file).read_text())
        return cls(version=raw["version"], url=raw["url"], sha256=raw["sha256"], licence=raw["licence"],
                   input_size=int(raw["input_size"]), classes={int(k): v for k, v in raw["classes"].items()},
                   path=Path(weights_dir) / raw["file"])


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(url: str, path: Path, sha256: str) -> Path:
    """``path``, downloaded from ``url`` if missing. A file with the wrong checksum is refused."""
    path = Path(path)
    if not path.is_file():
        path.parent.mkdir(parents=True, exist_ok=True)
        log.info("downloading %s", url)
        part = path.with_suffix(path.suffix + ".part")
        with urllib.request.urlopen(url, timeout=60) as response, open(part, "wb") as out:
            while block := response.read(1 << 20):
                out.write(block)
        part.replace(path)
    found = sha256_of(path)
    if found != sha256:
        raise SystemExit(f"{path}: sha256 is {found}, expected {sha256}. Delete the file or fix the config.")
    return path


class YoloxDetector:
    """YOLOX (ONNX) through cv2.dnn. Person and vehicle only; every other class is ignored."""

    STRIDES = (8, 16, 32)

    def __init__(self, model: ModelConfig, min_confidence: float = 0.4, nms_iou: float = 0.45):
        self.model = model
        self.min_confidence = min_confidence
        self.nms_iou = nms_iou
        self._net = cv2.dnn.readNetFromONNX(str(model.path))
        size = model.input_size
        grids, strides = [], []
        for stride in self.STRIDES:
            n = size // stride
            xs, ys = np.meshgrid(np.arange(n), np.arange(n))
            grids.append(np.stack((xs, ys), axis=2).reshape(-1, 2))
            strides.append(np.full((n * n, 1), stride))
        self._grid = np.concatenate(grids).astype(np.float32)
        self._stride = np.concatenate(strides).astype(np.float32)
        self._class_index = np.array(sorted(model.classes))
        # Several model classes (car, bus, truck) are one class to us.
        self._class_name = [model.classes[i] for i in self._class_index]

    def detect(self, frame: np.ndarray) -> list[Box]:
        size = self.model.input_size
        height, width = frame.shape[:2]
        scale = min(size / height, size / width)
        resized = cv2.resize(frame, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_LINEAR)
        padded = np.full((size, size, 3), 114, dtype=np.uint8)      # YOLOX: top-left, grey padding, raw BGR
        padded[: resized.shape[0], : resized.shape[1]] = resized
        self._net.setInput(cv2.dnn.blobFromImage(padded, 1.0, (size, size), swapRB=False))
        out = self._net.forward()[0]                                # (anchors, 5 + classes)

        centre = (out[:, :2] + self._grid) * self._stride / scale
        wh = np.exp(out[:, 2:4]) * self._stride / scale
        scores = out[:, 4:5] * out[:, 5:][:, self._class_index]     # objectness x class, our classes only
        best = scores.argmax(axis=1)
        confidence = scores[np.arange(len(scores)), best]
        keep = confidence >= self.min_confidence
        if not keep.any():
            return []
        centre, wh, best, confidence = centre[keep], wh[keep], best[keep], confidence[keep]
        top_left = centre - wh / 2
        rects = np.concatenate((top_left, wh), axis=1)
        names = [self._class_name[i] for i in best]
        boxes: list[Box] = []
        for name in set(names):                                     # NMS per class of ours
            idx = [i for i, n in enumerate(names) if n == name]
            kept = cv2.dnn.NMSBoxes(rects[idx].tolist(), confidence[idx].tolist(), self.min_confidence, self.nms_iou)
            for k in np.array(kept).reshape(-1):
                x, y, w, h = rects[idx[k]]
                x0, y0 = max(0.0, float(x)), max(0.0, float(y))     # clip to the frame
                x1, y1 = min(float(width), float(x + w)), min(float(height), float(y + h))
                if x1 - x0 >= 2 and y1 - y0 >= 2:
                    boxes.append(Box(name, float(confidence[idx[k]]), x0, y0, x1 - x0, y1 - y0))
        return boxes
