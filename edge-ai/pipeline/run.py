#!/usr/bin/env python3
"""Run the edge pipeline on a video file or a live camera: detector -> tracker -> geolocator -> EdgePublisher.

    cd edge-ai && .venv/bin/python -m pipeline.run                  # the test video, as tower-01
    .venv/bin/python -m pipeline.run --video clip.mp4 --config config/my-tower.yaml --loop
    .venv/bin/python -m pipeline.run --camera csi:0 --config config/tower-01.yaml --host ground.lan

A live camera (see pipeline/camera.py) is read newest frame first. When it
stops giving pictures the pipeline exits with status 1, so its service
restarts it.

The video is played at its own frame rate, like a live camera: when the
detector is slower than the video, frames are skipped, not queued. Each
confirmed track is published at most once every ``--every`` seconds, with a
picture the first time it is seen.

The ground position is the bottom centre of the box (the feet), put through
the camera's homography. A box cut off by the bottom of the frame has no
visible feet, so it is sent without a position.

Defaults fit the local development stack (make -C ops broker coordinator).
"""

from __future__ import annotations

import argparse
import logging
import signal
import sys
import time
from pathlib import Path

import cv2
import yaml

EDGE_DIR = Path(__file__).resolve().parent.parent
REPO = EDGE_DIR.parent
sys.path.insert(0, str(EDGE_DIR))

from geo.homography import GroundHomography  # noqa: E402
from pipeline.camera import Camera, CameraError, Capture, describe  # noqa: E402
from pipeline.detector import ModelConfig, YoloxDetector, fetch  # noqa: E402
from pipeline.publisher import EdgePublisher  # noqa: E402
from pipeline.tracker import IouTracker  # noqa: E402
from pipeline.video import Video  # noqa: E402

log = logging.getLogger("edge")


def schema_check():
    """The coordinator's own message check, when this runs inside the repo; None on a device."""
    try:
        sys.path.insert(0, str(REPO / "ground-core"))
        from coordinator.schemas import MessageValidator
        return MessageValidator(REPO / "schemas").check
    except (ImportError, FileNotFoundError):
        return None


def device_token(path: Path, source: str) -> str | None:
    """The token for ``source`` from a file of ``id=token`` lines, or a file holding just the token."""
    if not path.is_file():
        return None
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip() and not line.startswith("#")]
    for line in lines:
        name, sep, token = line.partition("=")
        if sep and name.strip() == source:
            return token.strip()
    return lines[0] if len(lines) == 1 and "=" not in lines[0] else None


def foot_sigma_px(box_h: float) -> float:
    """How well a box's bottom edge marks the feet, one sigma, in pixels.

    A guess until spike S4 measures it: a tenth of the box height (legs apart,
    shadows, a loose box), and never under 4 pixels (the detector works on a
    picture scaled down to 416 pixels).
    """
    return max(4.0, 0.1 * box_h)


def picture(frame, box, max_width: int = 640) -> bytes | None:
    """The frame with the box drawn, as a JPEG small enough to upload."""
    shown = frame.copy()
    cv2.rectangle(shown, (int(box.x), int(box.y)), (int(box.x + box.w), int(box.y + box.h)), (0, 0, 255), 2)
    if shown.shape[1] > max_width:
        shown = cv2.resize(shown, (max_width, round(shown.shape[0] * max_width / shown.shape[1])))
    ok, jpeg = cv2.imencode(".jpg", shown, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return jpeg.tobytes() if ok else None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--config", type=Path, default=EDGE_DIR / "config" / "test-video.yaml",
                    help="camera config: source id, video, control points")
    feed = ap.add_mutually_exclusive_group()
    feed.add_argument("--video", type=Path, help="video file (default: the one the config names)")
    feed.add_argument("--camera", help="a live camera instead of a video: 0 (USB), csi:0 (Jetson CSI), "
                                       "rtsp://... or gst:<pipeline>; the config must give camera.capture")
    ap.add_argument("--model", type=Path, default=EDGE_DIR / "models" / "yolox-tiny.yaml")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--port", type=int, default=8883)
    ap.add_argument("--ca", default=str(REPO / "ops" / "certs" / "ca.crt"), help="CA certificate for broker and coordinator")
    ap.add_argument("--no-tls", action="store_true", help="plain MQTT, for a test broker only")
    ap.add_argument("--password-file", type=Path, help="MQTT password file (default ops/secrets/mqtt/<source>.password)")
    ap.add_argument("--snapshot-url", default="https://localhost:8443/api/v1/snapshots",
                    help="where pictures are uploaded; empty for none")
    ap.add_argument("--device-token-file", type=Path, default=REPO / "ops" / "secrets" / "device.tokens")
    ap.add_argument("--queue", type=Path, help="disk queue file (default var/queue-<source>.sqlite)")
    ap.add_argument("--every", type=float, default=1.0, help="seconds between detections of one track")
    ap.add_argument("--min-confidence", type=float, default=0.4)
    ap.add_argument("--loop", action="store_true", help="start the video again when it ends")
    ap.add_argument("--duration", type=float, default=0, help="seconds to run; 0 runs to the end of the video")
    args = ap.parse_args()
    if args.camera is not None and args.loop:
        ap.error("--loop is for a video file, not a live camera")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    config = yaml.safe_load(args.config.read_text())
    source = config["source"]
    camera = config["camera"]
    try:
        locator = GroundHomography([(p["px"][0], p["px"][1], p["lat"], p["lon"]) for p in camera["points"] or []],
                                   control_error_m=camera["control_error_m"],
                                   max_error_m=camera.get("max_error_m", 30.0))
    except ValueError as e:
        raise SystemExit(f"{args.config.name}: {e}") from None

    live = args.camera is not None
    try:
        capture = Capture.from_config(camera.get("capture"))
    except CameraError as e:
        raise SystemExit(f"{args.config.name}: {e}") from None
    if live and not capture.sized:
        raise SystemExit(f"{args.config.name}: a live camera needs camera.capture.width and height, "
                         "the picture size the control points were measured on")
    video = args.video
    if not live and video is None:
        v = config["video"]
        video = fetch(v["url"], EDGE_DIR / "var" / "video" / v["file"], v["sha256"])
    model = ModelConfig.load(args.model, EDGE_DIR / "var" / "models")
    fetch(model.url, model.path, model.sha256)
    detector = YoloxDetector(model, min_confidence=args.min_confidence)
    # Ids start from the clock so that a restart never reuses an id the coordinator still remembers.
    tracker = IouTracker(first_id=int(time.time()) % 100_000 * 100)

    password_file = args.password_file or REPO / "ops" / "secrets" / "mqtt" / f"{source}.password"
    token = device_token(args.device_token_file, source) if args.snapshot_url else None
    if args.snapshot_url and token is None:
        log.warning("no device token for %s in %s: detections go without pictures", source, args.device_token_file)
    check = schema_check()
    feed = describe(args.camera) if live else f"video {video.name}"
    # Open the camera before connecting, so a missing camera stops here, not with the publisher running.
    try:
        cap = Camera(args.camera, capture) if live else Video(video)
    except CameraError as e:
        raise SystemExit(str(e)) from None
    log.info("source %s, model %s, %s (%s), schema check %s", source, model.version, feed, cap.backend,
             "on" if check else "off")
    publisher = EdgePublisher(
        source, args.host, args.port, password=password_file.read_text().strip(),
        ca_file=args.ca, tls=not args.no_tls, queue_path=args.queue or EDGE_DIR / "var" / f"queue-{source}.sqlite",
        model_version=model.version, model_sha256=model.sha256,
        snapshot_url=args.snapshot_url or None, device_token=token, check=check)
    publisher.start()
    if not publisher.wait_connected(3):
        log.warning("no broker yet (%s): detections wait in the disk queue",
                    publisher.last_error or f"nothing at {args.host}:{args.port}")

    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    video_fps = cap.fps
    failed = False
    started = time.monotonic()
    frame_no = 0                    # frames gone by, read or skipped; not reset by --loop, so it is a video's clock
    frames_done = skipped = 0
    last_sent: dict[int, float] = {}
    pictured: set[int] = set()
    report_at, report_frames = started + 5.0, 0

    while not stopping:
        now = time.monotonic()
        if args.duration and now - started >= args.duration:
            break
        if not live:
            # Keep to the video's clock: wait when early, drop frames when late.
            due = started + frame_no / video_fps
            if now < due:
                time.sleep(due - now)
            while time.monotonic() - due > 1.0 / video_fps and cap.skip():
                frame_no += 1
                skipped += 1
                due = started + frame_no / video_fps
        try:
            frame = cap.read()
        except CameraError as e:
            log.error("%s", e)
            failed = True
            break
        if frame is None:
            if live:
                log.error("%s stopped giving pictures", feed)
                failed = True
                break
            if not args.loop:
                break
            cap.rewind()
            tracker.reset()         # the scene jumps back: the old tracks are not these people
            continue
        frame_no += 1
        frames_done += 1
        made_s = time.time()
        height, width = frame.shape[:2]

        # The tracker's clock: the video's own time, or the wall clock for a live camera.
        seen_s = time.monotonic() - started if live else frame_no / video_fps
        for track in tracker.update(detector.detect(frame), seen_s):
            now = time.monotonic()
            if now - last_sent.get(track.track_id, -1e9) < args.every:
                continue
            box = track.box
            geo = None
            if box.y + box.h < height - 2:      # feet in the picture
                geo = locator.locate(box.x + box.w / 2, box.y + box.h, foot_sigma_px(box.h))
            first = track.track_id not in pictured
            taken = publisher.publish_detection(
                box.cls, box.confidence, track.track_id,
                {"x": box.x / width, "y": box.y / height, "w": box.w / width, "h": box.h / height},
                geo=geo, jpeg=picture(frame, box) if first else None, made_s=made_s)
            if taken:
                last_sent[track.track_id] = now
                pictured.add(track.track_id)
                if first:
                    where = f"{geo['lat']:.6f},{geo['lon']:.6f} ±{geo['error_m']:.1f} m" if geo else "no ground position"
                    log.info("track %d: %s %.2f at %s", track.track_id, box.cls, box.confidence, where)

        now = time.monotonic()
        if now >= report_at:
            fps = (frames_done - report_frames) / (now - report_at + 5.0)
            # Under half the camera's rate, tracks start to break: say so in edge.status.
            publisher.set_health(fps=fps, degraded="slow" if fps < video_fps / 2 else None)
            log.info("%.1f frames/s (feed %.1f), %d skipped, queue %d, %s", fps, video_fps, skipped,
                     publisher.queue_len, dict(publisher.stats))
            report_at, report_frames = now + 5.0, frames_done

    cap.close()
    publisher.stop()
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
