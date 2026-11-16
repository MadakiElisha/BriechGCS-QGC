"""The tower homography gives positions with an error that grows with range; the tracker holds ids."""

import math

import pytest

from geo.homography import METRES_PER_DEG_LAT, GroundHomography
from pipeline.detector import Box
from pipeline.tracker import IouTracker, iou

LAT0, LON0 = 6.5240, 3.3790
M_PER_DEG_LON = METRES_PER_DEG_LAT * math.cos(math.radians(LAT0))

# A pinhole camera 8 m up, looking north and 30 degrees down, 800 px focal length, 768x576.
HEIGHT_M, TILT, FOCAL, CU, CV = 8.0, math.radians(30), 800.0, 384.0, 288.0
HORIZON_ROW = CV - FOCAL * math.tan(TILT)


def pixel_of(east: float, north: float) -> tuple[float, float]:
    depth = north * math.cos(TILT) + HEIGHT_M * math.sin(TILT)
    down = -north * math.sin(TILT) + HEIGHT_M * math.cos(TILT)
    return CU + FOCAL * east / depth, CV + FOCAL * down / depth


def lat_lon(east: float, north: float) -> tuple[float, float]:
    return LAT0 + north / METRES_PER_DEG_LAT, LON0 + east / M_PER_DEG_LON


def control(points):
    return [(*pixel_of(e, n), *lat_lon(e, n)) for e, n in points]


@pytest.fixture
def camera() -> GroundHomography:
    return GroundHomography(control([(-5, 8), (5, 8), (8, 25), (-8, 25), (0, 15)]), control_error_m=1.0)


def metres_off(found: dict, east: float, north: float) -> float:
    lat, lon = lat_lon(east, north)
    return math.hypot((found["lat"] - lat) * METRES_PER_DEG_LAT, (found["lon"] - lon) * M_PER_DEG_LON)


def test_known_ground_points_come_back_within_a_centimetre(camera):
    assert camera.fit_rms_m < 0.01
    for east, north in [(0, 10), (-6, 20), (7, 12), (3, 40)]:
        found = camera.locate(*pixel_of(east, north), sigma_px=4.0)
        assert metres_off(found, east, north) < 0.01


def test_error_is_never_under_the_survey_error_and_grows_with_range(camera):
    near = camera.locate(*pixel_of(0, 10), sigma_px=4.0)["error_m"]
    far = camera.locate(*pixel_of(0, 40), sigma_px=4.0)["error_m"]
    assert camera.control_error_m < near < far
    # At 40 m one pixel row covers about 0.2 m of ground: 4 px is most of a metre.
    assert 1.2 < far < 2.0


def test_the_stated_error_covers_a_wrong_foot_pixel(camera):
    u, v = pixel_of(2, 30)
    shifted = camera.locate(u, v - 4.0, sigma_px=4.0)        # the box ends 4 px above the feet
    assert metres_off(shifted, 2, 30) < shifted["error_m"]


def test_no_position_at_or_above_the_horizon(camera):
    assert camera.locate(384, HORIZON_ROW - 1, sigma_px=4.0) is None
    assert camera.locate(384, HORIZON_ROW - 100, sigma_px=4.0) is None
    assert camera.locate(384, HORIZON_ROW + 2, sigma_px=4.0) is None     # below it, but hundreds of metres out


def test_a_vague_position_is_withheld_not_sent(camera):
    u, v = pixel_of(0, 40)
    assert camera.locate(u, v, sigma_px=4.0) is not None
    camera.max_error_m = 1.1
    assert camera.locate(u, v, sigma_px=4.0) is None


def test_more_points_show_a_bad_survey_in_the_error():
    points = control([(-5, 8), (5, 8), (8, 25), (-8, 25), (0, 15)])
    u, v, lat, lon = points[4]
    points[4] = (u, v, lat + 3.0 / METRES_PER_DEG_LAT, lon)             # one point surveyed 3 m off
    camera = GroundHomography(points, control_error_m=1.0)
    assert camera.fit_rms_m > 0.5
    assert camera.locate(*pixel_of(0, 10), sigma_px=1.0)["error_m"] > math.hypot(1.0, 0.5)


def test_bad_control_points_are_refused():
    with pytest.raises(ValueError):
        GroundHomography(control([(-5, 8), (5, 8), (8, 25)]), control_error_m=1.0)
    with pytest.raises(ValueError):
        GroundHomography(control([(0, 8), (0, 12), (0, 20), (0, 30)]), control_error_m=1.0)   # in a line
    with pytest.raises(ValueError):
        GroundHomography(control([(-5, 8), (5, 8), (8, 25), (-8, 25)]), control_error_m=0.0)


# -- tracker ------------------------------------------------------------------

def person(x: float, y: float = 100.0) -> Box:
    return Box("person", 0.9, x, y, 40.0, 100.0)


def test_iou():
    assert iou(person(0), person(0)) == pytest.approx(1.0)
    assert iou(person(0), person(20)) == pytest.approx(1 / 3)
    assert iou(person(0), person(40)) == 0.0


def test_a_track_is_reported_after_three_frames_and_keeps_its_id():
    tracker = IouTracker(first_id=500)
    assert tracker.update([person(0)], 0.0) == []
    assert tracker.update([person(4)], 0.1) == []
    ids = [t.track_id for i, x in enumerate((8, 12, 16)) for t in tracker.update([person(x)], 0.2 + i / 10)]
    assert ids == [500, 500, 500]


def test_a_one_frame_false_detection_uses_up_no_id():
    tracker = IouTracker()
    tracker.update([person(0), person(500)], 0.0)       # the second is never seen again
    for i in range(1, 4):
        tracks = tracker.update([person(0)], i / 10)
    assert [t.track_id for t in tracks] == [1]
    for i in range(4, 8):
        tracks = tracker.update([person(0), person(300)], i / 10)
    assert sorted(t.track_id for t in tracks) == [1, 2]


def test_two_people_keep_their_own_ids_and_a_new_one_gets_a_new_id():
    tracker = IouTracker(min_hits=1)
    for step in range(5):
        tracks = tracker.update([person(step * 5), person(300 - step * 5)], step / 10)
    assert sorted(t.track_id for t in tracks) == [1, 2]
    by_id = {t.track_id: t.box.x for t in tracks}
    assert by_id[1] < 100 < by_id[2]
    tracks = tracker.update([person(25), person(275), person(600)], 0.5)
    assert sorted(t.track_id for t in tracks) == [1, 2, 3]


def test_dropped_frames_do_not_break_a_walking_track():
    # 60 px/s in a 40 px wide box at 3 frames/s: old and new boxes overlap by a third (IoU 0.33)
    # and by nothing at all after one more dropped frame. The motion carries the id across.
    tracker = IouTracker(min_hits=1)
    ids = {t.track_id for i in range(6) for t in tracker.update([person(i * 20)], i / 3)}
    ids |= {t.track_id for t in tracker.update([person(5 * 20 + 50)], 5 / 3 + 5 / 6)}      # a gap of 2.5 frames
    assert ids == {1}


def test_a_short_gap_keeps_the_id_and_a_long_one_does_not():
    tracker = IouTracker(min_hits=1, max_gap_s=1.0)
    tracker.update([person(0)], 0.0)
    tracker.update([], 0.4)
    assert [t.track_id for t in tracker.update([person(5)], 0.8)] == [1]
    tracker.update([], 1.5)
    assert [t.track_id for t in tracker.update([person(5)], 2.0)] == [2]


def test_a_person_and_a_vehicle_in_the_same_place_are_two_tracks():
    tracker = IouTracker(min_hits=1)
    tracker.update([person(0)], 0.0)
    tracks = tracker.update([Box("vehicle", 0.8, 0.0, 100.0, 40.0, 100.0)], 0.1)
    assert [(t.track_id, t.box.cls) for t in tracks] == [(2, "vehicle")]


def test_reset_forgets_tracks_but_never_reuses_an_id():
    tracker = IouTracker(min_hits=1)
    tracker.update([person(0)], 0.0)
    tracker.reset()
    assert [t.track_id for t in tracker.update([person(0)], 0.1)] == [2]
