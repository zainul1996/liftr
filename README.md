# LIFTR

Lift more. Log less.

LIFTR is a private, offline-first Apple Watch strength-training project with a native iPhone companion. Run 1 collects labelled wrist-motion recordings. Later runs will use real Apple Watch data to evaluate exercise recognition, repetition counting and set detection.

This build does not predict exercises or count repetitions automatically. Enter the repetitions you actually completed. There is no backend, login, subscription or cloud inference.

## Current implementation

- SwiftUI Watch recording, exercise selection, machine variant, actual reps and weight entry.
- HealthKit strength-training workout lifecycle and Core Motion capture targeting 50 Hz.
- Raw acceleration, angular velocity, gravity, attitude quaternion and monotonic timestamps.
- Disk-streamed recording files, local recording summaries and interrupted-draft recovery.
- Queued WatchConnectivity file transfer, UUID deduplication, explicit iPhone acknowledgement and retry.
- iPhone recording list, detail, motion waveform, sampling diagnostics, correction history and JSON sharing.
- Shared Codable schema, Python validation, automated tests and separate simulator build scripts.

See the [architecture](docs/architecture.md), [data schema](docs/data-schema.md), [collection guide](docs/data-collection.md) and [device test procedure](docs/device-testing.md).

## Exercise library

| Stable ID | Display name |
| --- | --- |
| `machine_chest_press` | Machine Chest Press |
| `machine_shoulder_press` | Machine Shoulder Press |
| `cable_fly_high_low` | High-to-Low Chest Fly |
| `cable_fly_mid` | Mid-Height Chest Fly |
| `cable_fly_low_high` | Low-to-High Chest Fly |
| `dumbbell_bicep_curl` | Dumbbell Bicep Curl |
| `machine_triceps_extension` | Machine Triceps Extension |
| `seated_leg_extension` | Seated Leg Extension |
| `seated_leg_curl` | Seated Leg Curl |

The leg machine names are provisional. Display names and equipment variants may change while stable IDs preserve existing recordings. Every exercise is currently manual. Automatic and assisted capability labels require measured held-out results.

## Development prerequisites

Use a Mac with full Xcode and compatible iOS/watchOS SDKs. The project targets iOS 17 and watchOS 10 or later, uses Swift 6, and was initially compiled using Xcode 26.4.1. CI selects Xcode 26.2 on a macOS runner. XcodeGen 2.44 or later regenerates the checked-in project. Python 3.10 or later runs the standard-library validator without third-party packages.

Install Xcode from Apple, open it once and install the SDK components you need. If Homebrew is available, install the project generator:

```sh
brew install xcodegen
```

The scripts use `/Applications/Xcode.app/Contents/Developer` by default. Set `DEVELOPER_DIR` explicitly if Xcode is installed elsewhere. They do not change the Mac's global developer-directory setting.

## Personal GitHub setup

The repository is [zainul1996/liftr](https://github.com/zainul1996/liftr), private and owned by a personal account. On the development Mac, sign into that personal GitHub account using GitHub Desktop or GitHub CLI. Never put a token in a clone URL or source file.

```sh
mkdir -p ~/Documents/personal
cd ~/Documents/personal
gh repo clone zainul1996/liftr
cd liftr
```

If testing an unmerged development checkpoint, select the branch named in its handoff before building. `main` can remain at the stable baseline while an integration pull request is under review.

## Family MacBook setup

Create a separate macOS user account for this project. Install Xcode there and add the project owner's Apple Account in Xcode Settings, Accounts. Do not change another family member's iCloud account.

Use an iPhone paired to the intended Apple Watch. Connect the iPhone to the Mac and follow Apple's device trust and Developer Mode prompts. Keep both devices unlocked during initial setup. A signing team must support the capabilities in this project. Simulator compilation does not validate HealthKit provisioning on a Personal Team. TestFlight and App Store distribution require the appropriate Apple Developer membership and separate release authorization.

## Build the apps

The repository includes `LIFTR.xcodeproj`. Open it directly in Xcode. Regenerate after adding or renaming app source files:

```sh
./scripts/bootstrap.sh
```

Bootstrap checks Xcode, generates the project and creates `.venv`. It does not sign in, install the app or alter signing credentials.

For simulator compilation from Terminal:

```sh
./scripts/build-ios.sh
./scripts/build-watch.sh
```

These are unsigned builds. The iPhone target embeds its Watch companion. The separate Watch build checks the Watch target directly. They do not start a recording or prove that physical sensors and transfers work.

For physical installation:

1. Open `LIFTR.xcodeproj` and select the LIFTR iPhone target.
2. In Signing & Capabilities choose the project owner's team. Keep automatic signing enabled.
3. Choose the connected iPhone, build and run.
4. Select the LIFTRWatch target, choose the paired Apple Watch, then build and run.
5. If the generic bundle ID is unavailable, use your own unique iPhone identifier and a Watch identifier with the same prefix. Update `WKCompanionAppBundleIdentifier` to match the iPhone identifier. Apply durable changes in `project.yml`, then regenerate.
6. Grant the requested workout and motion permissions when recording starts.
7. Perform the short device smoke test in [device-testing.md](docs/device-testing.md) before collecting gym data.

Do not commit your team settings, provisioning profiles or certificates. An entitlement or provisioning error must be resolved with the selected signing team before device validation.

## Collect a set

On Watch, choose the exercise and optional machine variant before recording. Tap Start Workout for the first set. Complete the movement, then tap End Set. Enter actual repetitions and weight in kilograms, then Save Set.

The app returns to rest and keeps the same exercise for the next set. Change exercise when you change machines. End Workout when finished. A disconnected iPhone does not prevent local recording. Saved recordings stay on Watch until transfer can complete. Retry iPhone transfer from the Watch recordings list if needed.

Use the actual rep count, not the number of visible signal peaks. Keep a consistent pseudonymous participant identity. The Watch generates a local participant UUID, a session UUID and stable recording UUIDs. Wrist, hardware identifier, OS version, units and sensor settings accompany each recording.

Record across several gym sessions, weights and speeds. The initial upper-body goal is 20 to 30 sets per exercise. Leg tracking is an experiment, with 15 sets per machine and negative examples. Do not turn these targets into an unsafe training schedule. Collect gradually during normal workouts.

Interrupted recordings are retained as drafts. Recover them from the Watch home screen. Recovery labels them interrupted and leaves actual reps unknown. Inspect them on iPhone before including them in a dataset.

## Review, correct and export

Open LIFTR on the paired iPhone. Background delivery may take time. The recordings tab shows local copies. Open a recording to inspect its label, raw acceleration waveform, sample count, observed sampling rate and gaps.

Corrections use a separate review history. The original stored recording stays intact. A reviewed export includes the effective metadata and annotations, original metadata/annotations, and correction history. The samples remain raw. The export button uses the system share sheet. Choose Save to Files or another destination you trust. Export one recording from its detail screen or all recordings from the list.

Deleting from iPhone removes that device's copy. Watch files, system backups and previously exported files are separate. Do not assume deletion propagates to them.

## Validate exported data

No Python dependencies are needed for Run 1 validation. The optional environment remains isolated from the system Python:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r ml/requirements-validation.txt
python ml/validation/validate_recording.py /path/to/exported-file.liftr.json --json
python ml/validation/validate_recording.py /path/to/exported-directory --json
```

The validator rejects incompatible versions, missing labels for completed sets, nonfinite channels, reversed/duplicate timestamps, invalid quaternions and misaligned annotations. It reports actual sampling rates and gaps rather than assuming perfectly regular samples. Review warnings before training. Interrupted data and unrevised labels are not silently considered clean ground truth.

## Tests and CI

```sh
./scripts/test.sh
```

The script runs portable Swift tests, Python schema tests, then encodes a clearly synthetic Swift recording and validates it with Python. The synthetic fixture stays in ignored `.build` storage and is never training evidence.

Check formatting with Xcode's bundled formatter:

```sh
xcrun swift-format lint --strict --recursive packages apps tests/swift
```

GitHub Actions runs tests, schema compatibility, formatting and independent iPhone/Watch simulator builds. Workflows have read-only repository permission and no signing/release secrets. CI never trains a production model or publishes an application. Check the specific commit's results before claiming it passes.

## Models and future runs

Run 2 will validate the owner's real Apple Watch recordings, split by held-out session, compare a feature baseline and lightweight CNN, evaluate hierarchical fly recognition, implement confidence handling, count repetitions and integrate a measured Core ML model. Those commands and models do not exist in Run 1.

Run 3 will use new real-world feedback to improve accuracy, battery, interruption recovery, history and progress analytics, then prepare an approved beta. Do not interpret successful recording tests as a recognition benchmark.

## Troubleshooting

- If `xcodebuild` says only CommandLineTools is active, use the scripts or set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the command.
- If Xcode reports a missing simulator platform, install the matching platform in Xcode Settings, Components.
- If no samples arrive, test on a physical Watch, confirm permissions and check the sensor-unavailable message. A simulator cannot validate real wrist motion.
- If a set cannot save, enter actual reps and confirm samples were captured. Storage failures keep the local data for retry or draft recovery.
- If files do not arrive, keep both apps installed on paired physical devices. Open each app, wait for background delivery and use Retry iPhone transfer. Delivery and durable iPhone import acknowledgement are separate states.
- If schema validation fails, preserve the original export. Correct labels through the app or report the non-sensitive validation error. Never modify raw sample timestamps to make tests pass.
- If signing fails, check the selected team, unique bundle IDs and HealthKit capability. No signing material belongs in Git.

## Privacy and release status

See [privacy.md](docs/privacy.md). Intentional raw motion and workout labels remain local by default. Sharing is user initiated. Raw recordings, private datasets, credentials, certificates, provisioning profiles and build outputs are ignored by Git.

No TestFlight or App Store release workflow exists yet. No paid membership, signing credentials or production service is configured by this repository. Physical sampling, background reliability, paired-device transfer, storage interruption behaviour and battery use need the documented device checks. Report those results separately from code, compilation, unit tests and simulator launches.
