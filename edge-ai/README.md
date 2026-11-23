# Edge pipeline (edge-ai)

What runs on the edge computer beside a camera (handoff section 9):

```
camera frame -> detector -> tracker -> geolocator -> publisher -> MQTT broker
```

Today it runs on a video file and a laptop CPU. The publisher is the finished
part; the detector, tracker and geolocation are small first versions that
prove the chain with real pictures.

## Run it on the test video

```sh
make -C ops broker && make -C ops coordinator    # terminal 1 (not dev-up: its fake publisher is tower-01 too)
make -C ops probe                                # terminal 2
make -C ops edge-video                           # terminal 3; EDGE_ARGS="--loop" keeps it going
make -C ops edge-test                            # unit tests, no broker needed
```

The first run downloads the model (20 MB) and the test video (8 MB) into
`edge-ai/var/` and checks their SHA-256. The pipeline logs in as `tower-01`
and the probe prints its people and vehicles:

```
object.update o-tower-01-3684502 person 0.87 8.894635,7.265610 ±4.0m seen_by=tower-01
```

`python -m pipeline.run --help` (from `edge-ai/`, with `.venv/bin/python`)
lists the options: another video, another camera config, another broker.

## What is built

| Piece | File |
|---|---|
| `EdgePublisher`: `detection` and `edge.status` built to `schemas/`; status every 5 s, retained, offline last will; snapshot upload; disk queue, oldest first, `late` after 60 s; at most 10 detections a second | `pipeline/publisher.py` |
| Detector: YOLOX-tiny (ONNX) through OpenCV, person and vehicle only | `pipeline/detector.py`, `models/yolox-tiny.yaml` |
| Tracker: box overlap with a constant-speed guess, an id only after 3 frames | `pipeline/tracker.py` |
| Tower geolocation: homography from control points, with `error_m` | `geo/homography.py` |
| Video reader: OpenCV, or the `ffmpeg` command when OpenCV cannot decode the file | `pipeline/video.py` |
| Live camera: USB (`--camera 0`), Jetson CSI such as the IMX477 (`--camera csi:0`), RTSP, or any GStreamer pipeline; newest frame only; refuses pictures of another size than the control points were measured on | `pipeline/camera.py` |
| The loop that joins them: a video at its own speed, a camera as it comes; exits with status 1 when a camera stops, so its service restarts it | `pipeline/run.py` |
| The test video as tower-01's camera | `config/test-video.yaml` |
| The template for a real tower's camera (no control points until they are measured) | `config/tower-camera.example.yaml` |
| The service that runs it on a Jetson: on boot, restarted after a failure, logs in journald | `ops/systemd/briech-edge@.service` |

## Run it on a live camera

Copy `config/tower-camera.example.yaml` to `config/<tower-id>.yaml` and fill
it in at the site: `capture` (the picture size the camera is set to) and at
least four surveyed control points in pictures of that size. Then:

```sh
.venv/bin/python -m pipeline.run --camera csi:0 --config config/tower-01.yaml --host ground.lan   --snapshot-url https://ground.lan:8443/api/v1/snapshots
```

On a Jetson, the CSI camera needs an OpenCV with GStreamer: JetPack's own
(`sudo apt install python3-opencv`), not the pip wheel. Make the virtualenv
with `python3 -m venv --system-site-packages .venv` and install
`requirements.txt` without `opencv-python-headless`. Install the service as
`ops/systemd/briech-edge@.service` says.

On Windows, give `127.0.0.1` rather than `localhost` for `--host` and
`--snapshot-url`. Windows tries `localhost` over IPv6 first and waits about
two seconds per connection before falling back, and each picture upload holds
up the detections queued behind it (seen on 2026-11-23: the queue grew to
300; with `127.0.0.1` it stayed under 5).

## Using EdgePublisher from another detector

```python
from pipeline.publisher import EdgePublisher

pub = EdgePublisher("tower-01", "broker.lan", password=mqtt_password, ca_file="ca.crt",
                    queue_path="var/queue.sqlite", model_version="det-0.1.0", model_sha256=sha,
                    snapshot_url="https://ground.lan:8443/api/v1/snapshots", device_token=token)
pub.start()                          # returns at once; a late link is covered by the queue
pub.publish_detection("person", 0.91, track_id=17,
                      bbox={"x": 0.41, "y": 0.52, "w": 0.05, "h": 0.14},      # fractions of the frame
                      geo={"lat": 6.5251, "lon": 3.3801, "error_m": 6.0},     # or None: never a guess
                      jpeg=jpeg_bytes)                                        # optional, at most 300 KB
pub.set_health(fps=12.5)             # shown in the next edge.status
pub.stop()                           # sends what it can, says offline; the rest stays on disk
```

- Every detection is written to the disk queue first and removed when the
  broker acknowledges it (QoS 1). Delivery is at least once: around a
  reconnect the same detection, with the same `id`, can arrive twice.
- `publish_detection` returns `False` when the 10 a second limit is reached.
  A backlog is sent within the same limit, so keep normal traffic well under
  it or a backlog never clears. `run.py` sends each track once a second.
- A `geo` without an `error_m` greater than zero raises `ValueError`.
- `edge.status` says `degraded` while the oldest queued detection is over
  60 s old, or when `set_health(degraded="reason")` was called.
- It needs only `paho-mqtt`. Pass `check=` (the coordinator's
  `MessageValidator.check`) to test every message before it is sent; `run.py`
  does that whenever it runs inside this repo.

## How error_m is made

For a tower camera, one sigma, three parts added in quadrature
(`geo/homography.py`):

1. `control_error_m` from the camera config: how well the control points are
   known. Nothing this camera reports is better than that.
2. How far the fitted homography leaves the control points (needs more than
   four points to say anything).
3. How uncertain the feet are in the picture (a tenth of the box height, at
   least 4 pixels) times how many metres a pixel covers at that spot. This
   grows towards the horizon.

No position is sent, only the box, when the feet are cut off by the bottom
of the frame, when the pixel is at or above the horizon, or when the error
would be over `max_error_m` (30 m).

## What is not real yet

- **The test video's place on the map is invented.** Nobody surveyed that
  scene. The camera height and tilt are estimated from the clip (people taken
  as 1.7 m) and the lens is assumed; see `config/test-video.yaml`. Its
  `control_error_m` of 4 m is a judgement, not a measurement. Spike S4
  (geolocation accuracy) is still open and needs a real camera with surveyed
  points.
- **The model is a stand-in.** YOLOX-tiny pretrained on COCO, not fine-tuned
  on tower or aerial footage, not evaluated. Its code and weights are
  Apache-2.0; the COCO images it was trained on have mixed licences. That is
  written in `models/yolox-tiny.yaml`, and spike S9 still has to settle it.
- **No drone camera.** That needs the vehicle's position and attitude; only
  the tower case (homography) is built.
- **No TensorRT.** On a laptop CPU the
  pipeline did 4 to 9 frames a second on the 10 frames a second video,
  depending on what else the machine was running; the rest are skipped.
- **The tracker has no appearance model.** People who cross can swap ids, and
  someone hidden for over a second comes back with a new id, which the
  coordinator shows as a new object.

## Checked on 2026-11-16

macOS 15 (Intel), Python 3.10, broker in Docker, a coordinator on port 8444,
`sim/probe.py`:

- 30 s of the test video: 229 detections sent, 19 tracks; the probe printed
  248 `object.update` lines, positions in front of tower-01 sent with ±4.0 to
  ±4.1 m, none invalid; 19 pictures uploaded.
- Broker unreachable for 8 s: 52 detections waited on disk. With the broker
  back they were sent first, oldest first.
- `kill -9`: the probe showed `tower-01 link=offline` and the broker kept the
  retained offline status.
- The `late` flag is covered by a unit test only (`tests/test_publisher.py`),
  not by a real outage over 60 s.

The pip wheel of OpenCV for macOS Intel has no FFmpeg and cannot read the
test video; `pipeline/video.py` then uses the `ffmpeg` command
(`brew install ffmpeg`). Linux wheels read it directly.
