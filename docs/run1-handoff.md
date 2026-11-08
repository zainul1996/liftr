# Run 1 handoff

Run 1 implements labelled motion collection in one native Watch app and its iPhone companion. It does not include a trained classifier, automatic repetition counting or automatic set detection. Those require real labelled Apple Watch recordings in Run 2.

Repository: [private personal liftr repository](https://github.com/zainul1996/liftr). Follow-up validation and fixes are reviewed in [PR #2](https://github.com/zainul1996/liftr/pull/2), after the initial implementation in [PR #1](https://github.com/zainul1996/liftr/pull/1).

## Implemented features

- Native SwiftUI Watch recording and iPhone review applications, targeting iOS 17 and watchOS 10 or later.
- Nine stable exercise IDs, retained selection between sets, machine variants, actual repetitions and load in kilograms.
- HealthKit strength-workout lifecycle and streamed Core Motion collection targeting 50 Hz with measured monotonic timestamps, acceleration, rotation, gravity and attitude.
- Individual sets and optional continuous raw collection with explicit labelled intervals and unlabelled rest/transition samples.
- Durable raw JSON files, SQLite metadata/review/transfer state, interrupted partial and finalized-orphan recovery, and staged deletion with transactional interruption handling.
- Queued WatchConnectivity file transfer, UUID deduplication, retry and a durable import acknowledgement protocol. Actual paired delivery remains a device test.
- iPhone waveform and quality review, corrections preserving original labels and samples, native JSON sharing, and local deletion including app-owned reviewed export caches.
- Schema validation, isolated synthetic native UI tests, CI and physical setup instructions.

## Files and structure

`apps/watch` contains collection screens and workout coordination. `apps/ios` contains recording review, editing and sharing. `packages/LIFTRCore`, `LIFTRMotion`, `LIFTRPersistence` and `LIFTRSync` own shared schema, streaming/lifetime control, SQLite/raw persistence and transport respectively. `apps/testing` contains explicit simulator-only fixture support. `tests/swift`, `tests/python` and `tests/ui` contain portable and native UI checks. `project.yml`, `LIFTR.xcodeproj`, `scripts` and `.github/workflows/ci.yml` provide reproducible generation, builds and validation. The complete change lists are available in the linked pull requests.

No raw gym dataset, credentials, signing material or trained model is committed. Private JSON sidecars, SQLite journals and staged deletion files are ignored.

## Executed build and test evidence

Local toolchain: Xcode 26.4.1 (17E202), Apple Swift 6.3.1, Python 3.13.12. CI portable/build checks use Xcode 26.2 on macOS 15; native UI checks use the locally validated Xcode 26.4.1 on macOS 26. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when the global selection is CommandLineTools.

| Gate | Executed result |
| --- | --- |
| Swift package tests | 34 passed, independently rerun on `a8567b0` |
| Python schema/CLI tests | 14 passed |
| Cross-language fixture | Swift-produced 101-sample JSON passes Python validation |
| iPhone and Watch native UI test builds | Both build-for-testing succeeded |
| Generic physical-device compilation | Unsigned Release iOS and standalone watchOS builds succeeded; no signing or installation |
| iPhone native UI | 7 passed: six normal workflows and one actual prior-format synthetic archive upgrade on `a8567b0` |
| Watch native UI | 9 passed on `db666a1` (46 mm); complete compact 40 mm set/rest flow passed on source-equivalent `c690777` with whole-frame Start/End/next-set actions |
| Hosted CI | Package/build checks stay pinned to Xcode 26.2; native UI uses Xcode 26.4.1. Final PR and post-merge main runs are linked from PR #2 before handoff |
| Physical device and gym | Not tested by agents |

The SQLite tests cover migration/reopen, failed-transaction source preservation, rollback, clock reversal, lowercase UUIDs, future-schema refusal, concurrent review appends, locked databases, raw-staging failures, committed/uncommitted deletion recovery, same-ID reimport and corrupt-index recovery. Capture tests verify stale callbacks cannot write into the next recording.

The iPhone upgrade test uses actual synthetic files created by the earlier app UI. It preserves the raw SHA, original review UUID/date and effective curl/12-rep/17.5-kg labels through upgrade and a second launch. The resulting reviewed export equals the earlier app export and passes Python with zero errors or warnings, 101 samples, measured 50 Hz and no gaps.

The Watch suite covers exercise selection, save/rest and retained exercise, three sets across two workout sessions, continuous set markers with active-recovery exclusion, deletion cancellation/confirmation, two failed recovery attempts, and injected motion/workout/storage errors. Filesystem and SQLite audits confirm the expected session IDs, no deleted raw/metadata/review/ACK copies, and original failed drafts retained without accumulating recovery scratch directories. Synthetic permission failures test application behavior, not actual HealthKit authorization.

Production Watch source is `c690777`; subsequent changes through the final UI-test snapshot are harness, CI or documentation changes. The final Git commit, independent review and hosted check results are available on the linked PR. The iPhone production source has not changed since the seven passing `a8567b0` cases.

These are simulator fixtures with visibly synthetic participant/device identities in isolated test storage. Simulator timers do not measure Watch sensor performance. Native share-sheet presentation and a valid generated file do not prove a particular external destination saved it.

## Known limits and unverified behavior

- Real Core Motion quality, HealthKit permission/signing, screen-off/background recording, paired transfer/acknowledgement, storage pressure, large continuous-file memory use, workout interruptions and 60–90-minute battery behavior require physical devices.
- Apple does not support WatchConnectivity file or user-info delivery in Simulator. Deterministic persistence tests and disabled test transport do not substitute for those checks.
- Start Workout and End Set are visible on the tested 40 mm and 46 mm simulators. Review inputs and Save Set use the normal scrollable form on a compact Watch.
- Continuous annotations can be viewed on iPhone; editing individual continuous intervals or precise rep boundaries is not implemented. Corrections on an ordinary single set preserve originals and ordered history.
- Deletion is local. Other-device copies, external exports and backups remain separate; Watch retry can redeliver an iPhone-deleted UUID. Automatic retention and coordinated deletion are later work.
- Corrupt-index recovery preserves private database/journal copies and reports that reviews or acknowledgements may need recovery. Those recovery copies are separate from active-record deletion. Busy/full/unsupported-version errors do not reset the database.
- Every exercise remains manual until real held-out recognition/counting results justify another capability.

## Exact next actions on the family MacBook

1. Use a separate macOS user, install compatible Xcode with iOS/watchOS components and install prerequisites: `brew install xcodegen python@3.13 gh`.
2. Authenticate to the personal GitHub account yourself. Clone with `gh repo clone zainul1996/liftr`, enter `liftr`, then use `git switch main` and `git pull --ff-only` for subsequent updates.
3. Run `./scripts/bootstrap.sh`, `./scripts/test.sh`, `./scripts/build-ios.sh` and `./scripts/build-watch.sh`.
4. Open `LIFTR.xcodeproj`, add your Apple Account in Xcode, and select your own signing team for both app targets. Resolve bundle identifiers and HealthKit provisioning as described in [device setup](device-testing.md). No family iCloud changes are needed.
5. Run scheme `LIFTR` on the paired iPhone, then `LIFTRWatch` on the physical Watch if needed. Grant permissions.
6. Follow the [short physical smoke test](device-testing.md): record, label and save two sets, verify persistence and delivery, review/export on iPhone, and validate with `python3.13 ml/validation/validate_recording.py /path/to/export --json`.
7. Complete the disconnected-phone/retry/acknowledgement, screen-off, interruption and battery checks before trusting a full gym dataset to the app. Keep verified exports as backup.
8. Collect the specified upper-body, leg-experiment and gym-negative examples across several sessions. Supply the recordings and observed device failures for Run 2.

## Recommended next run

Run 2 starts only after physical setup and real labelled Apple Watch data. Validate data quality and session coverage first, then compare baseline and lightweight models with held-out sessions, implement counting/set detection independently, and integrate only measured offline behavior. No production model has been trained in Run 1.
