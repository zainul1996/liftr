#!/usr/bin/env python3
"""Validate LIFTR v1 JSON exports. Uses only Python's standard library."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
from datetime import datetime
import json
import math
from pathlib import Path
from statistics import median
from typing import Any
from uuid import UUID

EXERCISES = frozenset({
    "machine_chest_press", "machine_shoulder_press", "cable_fly_high_low",
    "cable_fly_mid", "cable_fly_low_high", "dumbbell_bicep_curl",
    "machine_triceps_extension", "seated_leg_extension", "seated_leg_curl",
})
COORDINATE_FRAME = "CMDeviceMotion device axes, xArbitraryZVertical reference frame"


@dataclass
class ValidationReport:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    sample_count: int = 0
    observed_hz: float | None = None
    median_interval_seconds: float | None = None
    gap_count: int = 0

    @property
    def valid(self) -> bool:
        return not self.errors


def validate_recording(document: Any) -> ValidationReport:
    report = ValidationReport()

    def error(path: str, message: str) -> None:
        report.errors.append(f"{path}: {message}")

    def number(value: Any, path: str, *, minimum: float | None = None,
               integer: bool = False, optional: bool = False) -> bool:
        if optional and value is None:
            return True
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            error(path, "must be a finite number")
            return False
        if integer and not isinstance(value, int):
            error(path, "must be an integer")
            return False
        if minimum is not None and value < minimum:
            error(path, f"must be at least {minimum}")
            return False
        return True

    def nonempty(value: Any, path: str) -> None:
        if not isinstance(value, str) or not value.strip():
            error(path, "must be a nonempty string")

    def uuid(value: Any, path: str) -> None:
        try:
            if not isinstance(value, str):
                raise ValueError("not a string")
            UUID(value)
        except (ValueError, AttributeError):
            error(path, "must be a UUID string")

    def date(value: Any, path: str, optional: bool = False) -> datetime | None:
        if value is None and optional:
            return None
        try:
            if not isinstance(value, str):
                raise ValueError("not a string")
            result = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if result.tzinfo is None:
                raise ValueError("timezone required")
            return result
        except (ValueError, TypeError):
            error(path, "must be an ISO 8601 timestamp with timezone")
            return None

    def exercise(value: Any, path: str, optional: bool = False) -> None:
        if value is None and optional:
            return
        if not isinstance(value, str) or value not in EXERCISES:
            error(path, "must be a stable exercise ID in taxonomy v1")

    if not isinstance(document, dict):
        error("recording", "must be an object")
        return report
    metadata = document.get("metadata")
    samples = document.get("samples")
    annotations = document.get("annotations")
    if not isinstance(metadata, dict):
        error("metadata", "must be an object")
        metadata = {}
    for key in ("id", "sessionID"):
        uuid(metadata.get(key), f"metadata.{key}")
    for key in ("participantID", "watchWrist", "watchModel", "watchOSVersion"):
        nonempty(metadata.get(key), f"metadata.{key}")
    for key in ("schemaVersion", "taxonomyVersion"):
        if type(metadata.get(key)) is not int or metadata[key] != 1:
            error(f"metadata.{key}", "only version 1 is supported")
    for key, allowed in {
        "labelReviewStatus": {"unreviewed", "reviewed", "corrected"},
        "mode": {"set", "continuous"}, "status": {"complete", "interrupted"},
    }.items():
        if metadata.get(key) not in allowed:
            error(f"metadata.{key}", f"must be one of {', '.join(sorted(allowed))}")
    exercise(metadata.get("exerciseID"), "metadata.exerciseID", optional=metadata.get("mode") == "continuous" or metadata.get("status") == "interrupted")
    if metadata.get("equipment") is not None:
        nonempty(metadata["equipment"], "metadata.equipment")
    number(metadata.get("weightKG"), "metadata.weightKG", minimum=0, optional=True)
    number(metadata.get("actualReps"), "metadata.actualReps", minimum=0, integer=True, optional=True)
    if metadata.get("mode") == "set" and metadata.get("status") == "complete":
        if metadata.get("actualReps") is None:
            error("metadata.actualReps", "complete labelled sets need an actual rep count")
        nonempty(metadata.get("equipment"), "metadata.equipment")
    started = date(metadata.get("startedAt"), "metadata.startedAt")
    ended = date(metadata.get("endedAt"), "metadata.endedAt", optional=metadata.get("status") == "interrupted")
    if started and ended and ended < started:
        error("metadata.endedAt", "precedes startedAt")
    if metadata.get("status") == "interrupted":
        report.warnings.append("Interrupted recording: inspect before using for training.")
    if metadata.get("labelReviewStatus") == "unreviewed":
        report.warnings.append("Labels have not been reviewed.")
    config = metadata.get("sensorConfiguration")
    if not isinstance(config, dict):
        error("metadata.sensorConfiguration", "must be an object")
        config = {}
    target_hz = config.get("targetHz")
    good_hz = number(target_hz, "metadata.sensorConfiguration.targetHz", minimum=1)
    for key, expected in {
        "accelerationUnit": "g", "rotationRateUnit": "rad/s",
        "timestampUnit": "seconds_since_boot", "coordinateFrame": COORDINATE_FRAME,
    }.items():
        if config.get(key) != expected:
            error(f"metadata.sensorConfiguration.{key}", f"expected {expected!r}")
    timestamps: list[float] = []
    if not isinstance(samples, list) or len(samples) < 2:
        error("samples", "must contain at least two motion samples")
        samples = [] if not isinstance(samples, list) else samples
    report.sample_count = len(samples)
    for index, sample in enumerate(samples):
        path = f"samples[{index}]"
        if not isinstance(sample, dict):
            error(path, "must be an object")
            continue
        timestamp = sample.get("timestamp")
        if number(timestamp, path + ".timestamp", minimum=0):
            timestamps.append(timestamp)
            if len(timestamps) > 1 and timestamp <= timestamps[-2]:
                error(path + ".timestamp", "timestamps must strictly increase, without duplicates")
        for channel in ("userAcceleration", "rotationRate", "gravity", "attitude"):
            vector = sample.get(channel)
            if not isinstance(vector, dict):
                error(path + "." + channel, "must be an object")
                continue
            axes = ("x", "y", "z", "w") if channel == "attitude" else ("x", "y", "z")
            valid = [number(vector.get(axis), f"{path}.{channel}.{axis}") for axis in axes]
            if channel == "attitude" and all(valid):
                norm = math.sqrt(sum(vector[axis] ** 2 for axis in axes))
                if not 0.85 <= norm <= 1.15:
                    error(path + ".attitude", "quaternion must have approximately unit length")
    if len(timestamps) >= 2 and all(b > a for a, b in zip(timestamps, timestamps[1:])):
        intervals = [b - a for a, b in zip(timestamps, timestamps[1:])]
        report.median_interval_seconds = median(intervals)
        report.observed_hz = (len(timestamps) - 1) / (timestamps[-1] - timestamps[0])
        if good_hz:
            report.gap_count = sum(delta > 2.5 / target_hz for delta in intervals)
            if report.gap_count:
                report.warnings.append(f"{report.gap_count} sample gaps exceed 2.5 target intervals; do not assume regular sampling.")
            if abs(report.observed_hz - target_hz) / target_hz > 0.1:
                report.warnings.append("Observed sample rate differs from target by more than 10%.")
        if started and ended and timestamps[-1] - timestamps[0] > (ended - started).total_seconds() + 2:
            error("samples", "monotonic duration exceeds recording wall-clock duration by more than two seconds")
    if not isinstance(annotations, list):
        error("annotations", "must be an array, empty when no boundaries were marked")
        annotations = []
    seen: set[str] = set()
    previous_end: float | None = None
    for index, annotation in enumerate(annotations):
        path = f"annotations[{index}]"
        if not isinstance(annotation, dict):
            error(path, "must be an object")
            continue
        annotation_id = annotation.get("id")
        uuid(annotation_id, path + ".id")
        if isinstance(annotation_id, str):
            if annotation_id.lower() in seen:
                error(path + ".id", "duplicate annotation UUID")
            seen.add(annotation_id.lower())
        exercise(annotation.get("exerciseID"), path + ".exerciseID")
        start, end = annotation.get("startTimestamp"), annotation.get("endTimestamp")
        good_start = number(start, path + ".startTimestamp", minimum=0)
        good_end = number(end, path + ".endTimestamp", minimum=0)
        number(annotation.get("actualReps"), path + ".actualReps", minimum=0, integer=True, optional=True)
        number(annotation.get("weightKG"), path + ".weightKG", minimum=0, optional=True)
        if good_start and good_end:
            if end <= start:
                error(path, "set end must follow set start")
            if previous_end is not None and start < previous_end:
                error(path, "set annotations must be chronological and must not overlap")
            previous_end = end
            if timestamps and (start < timestamps[0] - 1 or end > timestamps[-1] + 1):
                error(path, "set boundary is outside raw sample timeline, allowing one second for button/sensor latency")
            boundaries = annotation.get("repBoundaries")
            if boundaries is not None:
                if not isinstance(boundaries, list):
                    error(path + ".repBoundaries", "must be an array")
                else:
                    previous = None
                    for boundary in boundaries:
                        if number(boundary, path + ".repBoundaries"):
                            if boundary < start or boundary > end or previous is not None and boundary <= previous:
                                error(path + ".repBoundaries", "must increase within set boundaries")
                            previous = boundary
    return report


def validate_file(path: Path) -> ValidationReport:
    try:
        with path.open(encoding="utf-8") as source:
            document = json.load(source)
    except (OSError, ValueError) as exc:
        return ValidationReport(errors=[f"file: {exc}"])
    return validate_recording(document)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", type=Path, nargs="+", help="Recording JSON files or directories")
    parser.add_argument("--json", action="store_true", help="Print machine-readable reports")
    args = parser.parse_args(argv)
    paths: list[Path] = []
    for path in args.paths:
        paths.extend(sorted(path.glob("*.liftr.json")) if path.is_dir() else [path])
    if not paths:
        parser.error("no .liftr.json recordings found")
    results = [(str(path), validate_file(path)) for path in paths]
    if args.json:
        print(json.dumps([{**asdict(report), "path": path, "valid": report.valid} for path, report in results], indent=2, allow_nan=False))
    else:
        for path, report in results:
            print(f"{'PASS' if report.valid else 'FAIL'} {path}: {report.sample_count} samples, observed Hz={report.observed_hz}")
            for message in report.errors:
                print(f"  ERROR {message}")
            for message in report.warnings:
                print(f"  WARN {message}")
    return 0 if all(report.valid for _, report in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
