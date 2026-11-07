"""Synthetic schema/quality cases. No fixture is a real sensor recording."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ml" / "validation"))
from validate_recording import COORDINATE_FRAME, validate_recording, validate_file


def synthetic_recording():
    return {
        "metadata": {
            "id": "88888888-8888-4888-8888-888888888888",
            "participantID": "synthetic-test-only",
            "sessionID": "11111111-1111-4111-8111-111111111111",
            "exerciseID": "machine_chest_press", "equipment": "Synthetic test machine",
            "weightKG": 40.0, "actualReps": 2,
            "startedAt": "2026-11-07T21:00:00Z", "endedAt": "2026-11-07T21:00:02Z",
            "watchWrist": "left", "watchModel": "synthetic", "watchOSVersion": "synthetic",
            "sensorConfiguration": {"targetHz": 50.0, "accelerationUnit": "g",
                "rotationRateUnit": "rad/s", "timestampUnit": "seconds_since_boot",
                "coordinateFrame": COORDINATE_FRAME},
            "schemaVersion": 1, "taxonomyVersion": 1, "labelReviewStatus": "reviewed",
            "mode": "set", "status": "complete",
        },
        "samples": [{"timestamp": 100.0 + i * 0.02,
            "userAcceleration": {"x": 0.0, "y": 0.1, "z": 0.0},
            "rotationRate": {"x": 0.0, "y": 0.0, "z": 0.0},
            "gravity": {"x": 0.0, "y": -1.0, "z": 0.0},
            "attitude": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0}}
            for i in range(101)],
        "annotations": [{"id": "22222222-2222-4222-8222-222222222222",
            "exerciseID": "machine_chest_press", "startTimestamp": 100.0,
            "endTimestamp": 102.0, "actualReps": 2, "weightKG": 40.0,
            "repBoundaries": [100.1, 101.1]}],
    }


class ValidationTests(unittest.TestCase):
    def test_valid_synthetic_recording_reports_measured_sampling(self):
        report = validate_recording(synthetic_recording())
        self.assertTrue(report.valid, report.errors)
        self.assertEqual(report.sample_count, 101)
        self.assertAlmostEqual(report.observed_hz, 50.0)

    def test_duplicate_or_reversed_timestamps_rejected(self):
        for timestamp in [100.0, 99.9]:
            data = synthetic_recording()
            data["samples"][1]["timestamp"] = timestamp
            self.assertFalse(validate_recording(data).valid)

    def test_nan_and_boolean_sensor_channels_rejected(self):
        for value in [float("nan"), float("inf"), True, "0.1"]:
            data = synthetic_recording()
            data["samples"][4]["userAcceleration"]["x"] = value
            self.assertFalse(validate_recording(data).valid)

    def test_unknown_versions_and_units_rejected(self):
        for mutation in [lambda d: d["metadata"].update(schemaVersion=2),
                         lambda d: d["metadata"].update(taxonomyVersion=True),
                         lambda d: d["metadata"]["sensorConfiguration"].update(accelerationUnit="m/s2"),
                         lambda d: d["metadata"].update(exerciseID="generic_chest_fly")]:
            data = synthetic_recording()
            mutation(data)
            self.assertFalse(validate_recording(data).valid)

    def test_inconsistent_wall_clock_rejected(self):
        data = synthetic_recording()
        data["metadata"]["endedAt"] = "2026-11-07T20:59:59Z"
        self.assertFalse(validate_recording(data).valid)

    def test_unaligned_annotation_or_rep_boundary_rejected(self):
        for mutation in [lambda a: a.update(startTimestamp=10.0),
                         lambda a: a.update(endTimestamp=104.0),
                         lambda a: a.update(repBoundaries=[101.0, 100.5]),
                         lambda a: a.update(repBoundaries=[103.0])]:
            data = synthetic_recording()
            mutation(data["annotations"][0])
            self.assertFalse(validate_recording(data).valid)

    def test_overlapping_sets_rejected(self):
        data = synthetic_recording()
        second = copy.deepcopy(data["annotations"][0])
        second["id"] = "33333333-3333-4333-8333-333333333333"
        data["annotations"].append(second)
        self.assertFalse(validate_recording(data).valid)

    def test_sampling_gap_warns_without_inventing_samples(self):
        data = synthetic_recording()
        del data["samples"][30:40]
        report = validate_recording(data)
        self.assertTrue(report.valid, report.errors)
        self.assertEqual(report.gap_count, 1)
        self.assertEqual(report.sample_count, 91)

    def test_continuous_negative_recording_needs_no_exercise_label(self):
        data = synthetic_recording()
        data["metadata"].update(mode="continuous")
        for key in ["exerciseID", "actualReps", "weightKG", "equipment"]:
            data["metadata"].pop(key)
        data["annotations"] = []
        self.assertTrue(validate_recording(data).valid)

    def test_partial_and_malformed_json_fail_cleanly(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "broken.liftr.json"
            path.write_text('{"metadata":', encoding="utf-8")
            self.assertFalse(validate_file(path).valid)
        self.assertFalse(validate_recording({"metadata": [], "samples": "bad"}).valid)

    def test_invalid_shapes_and_extreme_numbers_fail_without_crashing(self):
        for mutation in [lambda d: d["metadata"].update(mode=[]),
                         lambda d: d["metadata"].update(labelReviewStatus={}),
                         lambda d: d["samples"][0].update(timestamp=10 ** 400),
                         lambda d: d["samples"][0]["attitude"].update(x=1e308)]:
            data = synthetic_recording()
            mutation(data)
            self.assertFalse(validate_recording(data).valid)

    def test_reviewed_export_retains_original_id_and_matches_latest_labels(self):
        data = synthetic_recording()
        data["originalMetadata"] = copy.deepcopy(data["metadata"])
        data["originalAnnotations"] = copy.deepcopy(data["annotations"])
        data["correctionHistory"] = [{"id": "44444444-4444-4444-8444-444444444444",
            "reviewedAt": "2026-11-07T22:00:00Z", "exerciseID": "machine_chest_press",
            "actualReps": 3, "weightKG": 45.0}]
        data["metadata"].update(actualReps=3, weightKG=45.0, labelReviewStatus="corrected")
        data["annotations"][0].update(actualReps=3, weightKG=45.0)
        self.assertTrue(validate_recording(data).valid)
        self.assertEqual(data["originalMetadata"]["actualReps"], 2)
        data["metadata"]["actualReps"] = 7
        self.assertFalse(validate_recording(data).valid)

    def test_complete_set_requires_actual_ground_truth(self):
        data = synthetic_recording()
        data["metadata"].pop("actualReps")
        self.assertFalse(validate_recording(data).valid)
        data["metadata"]["status"] = "interrupted"
        self.assertTrue(validate_recording(data).valid)

    def test_cli_success_failure_and_json_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.liftr.json"
            path.write_text(json.dumps(synthetic_recording()), encoding="utf-8")
            command = [sys.executable, str(ROOT / "ml/validation/validate_recording.py"), str(path), "--json"]
            valid = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(valid.returncode, 0, valid.stderr)
            self.assertTrue(json.loads(valid.stdout)[0]["valid"])
            data = synthetic_recording()
            data["samples"] = []
            path.write_text(json.dumps(data), encoding="utf-8")
            invalid = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(invalid.returncode, 1)


if __name__ == "__main__":
    unittest.main()
