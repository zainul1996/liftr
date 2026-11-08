# Recording schema v1

LIFTR exports one UTF-8 JSON file per recording, named `<UUID>.liftr.json`. The top-level fields are `metadata`, `samples`, and `annotations`. Swift `RecordingJSON` uses ISO 8601 dates. Optional Swift values may be absent rather than JSON null. The source of truth is `packages/LIFTRCore/Sources/Models.swift`.

Raw recording files remain separate from structured metadata, review history and transfer acknowledgements in the local `recording-index.sqlite` database. Only `*.liftr.json` files are training/export inputs. Do not commit raw recordings, exports or health data.

## Metadata

| Field | Meaning |
| --- | --- |
| `id` | Stable recording UUID, retained across retries and review exports |
| `participantID` | App-generated persistent pseudonymous UUID, never an Apple Account identifier |
| `sessionID` | Gym recording-session UUID, used for held-out session splits |
| `exerciseID` | Stable taxonomy ID, optional for continuous or interrupted recordings |
| `equipment` | Machine/equipment description, kept separately from exercise identity |
| `weightKG` | Optional entered load in kilograms, never inferred from motion |
| `actualReps` | Entered ground truth, optional when unknown or interrupted |
| `startedAt`, `endedAt` | ISO 8601 wall-clock dates, not sensor timestamps |
| `watchWrist` | Configured wrist |
| `watchModel`, `watchOSVersion` | Capture-device information |
| `sensorConfiguration` | Target rate, units, coordinate frame and timestamp convention |
| `schemaVersion`, `taxonomyVersion` | Both `1` for this schema |
| `labelReviewStatus` | `unreviewed`, `reviewed`, or `corrected` |
| `mode` | `set` or `continuous` |
| `status` | `complete` or `interrupted` |

A complete labelled set requires an exercise, equipment and actual rep count for validator acceptance. Zero reps means an explicit zero, not an unknown count. Use an interrupted recording or a continuous unlabelled interval for data without set-level ground truth.

## Raw samples

Every sample contains the following fields.

| Field | Shape and units |
| --- | --- |
| `timestamp` | Monotonic seconds since device boot from Core Motion |
| `userAcceleration` | `{x,y,z}`, acceleration with gravity removed, in g |
| `rotationRate` | `{x,y,z}`, radians per second |
| `gravity` | `{x,y,z}`, in g |
| `attitude` | Quaternion `{x,y,z,w}`, approximately unit length |

The initial `sensorConfiguration` is `targetHz: 50`, `accelerationUnit: "g"`, `rotationRateUnit: "rad/s"`, `timestampUnit: "seconds_since_boot"`, and `coordinateFrame: "CMDeviceMotion device axes, xArbitraryZVertical reference frame"`.

The vectors retain Core Motion device axes. An arbitrary vertical reference frame does not make acceleration a wrist position or a travel direction. Do not integrate acceleration and treat the result as ground truth displacement.

Measure the actual sample rate from timestamps. Do not silently fill gaps, drop samples, normalise the raw data, or force exact 20 ms spacing. Boot-relative times cannot be compared across different device boots. Wall-clock duration is only a coarse consistency check.

## Set annotations

Each annotation has `id`, `exerciseID`, `startTimestamp`, `endTimestamp`, optional `actualReps`, optional `weightKG`, and optional `repBoundaries`.

Annotation times share the raw sensor's monotonic timeline. Set intervals must be chronological and must not overlap. Samples outside explicit set annotations remain unlabelled context. Never label all continuous-session windows as the selected exercise.

Optional rep boundaries are precise manual annotations only when explicitly supplied. A set's total rep count does not provide individual rep locations. The schema does not assume whether an annotation scheme marks rep starts, ends, or whole cycles. Document that convention before using such annotations for evaluation.

## iPhone review exports

The iPhone keeps received raw recording files unchanged. Review history lives in SQLite and follows submission order, even when the wall clock changes. Earlier JSON metadata, `reviews.json` and transfer-acknowledgement files migrate transactionally on open; successful migrations remove the legacy copies only after commit. Failed migrations retain their sources and show a warning. An export with reviews includes:

- `metadata` with the latest exercise, actual reps and weight.
- `annotations` with the latest labels applied to the single set when it has one set annotation.
- `originalMetadata` and `originalAnnotations` preserving the received labels.
- `correctionHistory`, an ordered array of review UUID, `reviewedAt`, `exerciseID`, `actualReps` and `weightKG`.

The recording UUID and sensor samples stay unchanged. Continuous-session annotation editing is not available in the initial iPhone review screen. Standard Swift decoders ignore the additional review fields. Training adapters must deliberately choose reviewed labels and preserve original predictions or labels for evaluation.

## Validation

Run these commands from the repository root with Python 3.13.

```sh
python3.13 ml/validation/validate_recording.py /path/to/recording.liftr.json
python3.13 ml/validation/validate_recording.py /path/to/export-directory --json
python3.13 -m unittest discover -s tests/python -v
```

The validator exits with `0` for valid files, `1` for invalid files, and `2` for invalid CLI usage. It checks metadata, versions, stable exercise IDs, units, finite channels, monotonic time, annotation alignment and review consistency. It reports actual sample rate and sampling gaps. A gap is a warning, since rejecting all imperfect captures would hide data-quality problems. A passing schema check does not prove exercise labels or repetitions are accurate.

Directory validation selects `*.liftr.json`, excluding metadata summaries. There are no Python package dependencies for validation. Real data inspection, resampling and model training are later work.

## Local recovery and deletion

Raw-file deletion is staged alongside a SQLite transaction. On reopening, an uncommitted deletion restores the raw file; a committed deletion finishes its cleanup. Database locks or a staging failure retain the raw file and review history for retry. Unsupported future database versions are refused without downgrading them.

If SQLite explicitly reports a corrupt/non-database index, LIFTR preserves the database and its journal companions in `Index-Recovery-<UUID>` before rebuilding metadata from raw files. A visible warning explains that reviews and transfer acknowledgements may require recovery. These recovery files are private and can retain old labels; keep them local and include them when requesting storage recovery. Other database errors do not trigger a reset.
