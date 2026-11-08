# Run 1 architecture

The watch and iPhone apps share a local Swift package. LIFTRCore owns schema version 1 and the stable nine-exercise taxonomy. LIFTRPersistence stores canonical recordings under Application Support, using UUID filenames and atomic writes. LIFTRSync uses WatchConnectivity queued file transfers. LIFTRMotion collects and streams raw motion samples.

Each export is a standard UTF-8 JSON file with metadata, samples and annotations. A watch writer can append samples incrementally and add final metadata when the set finishes, so long recordings do not require one in-memory array. SQLite stores metadata, ordered review history and durable transfer acknowledgements; raw samples remain in separate immutable JSON files. Watch list/recovery reads metadata in bounded chunks. Legacy JSON sidecars migrate after a transactional commit. Raw deletion stages files together with a SQLite deletion marker, allowing rollback or cleanup after interruption.

The watch starts a HealthKit strength-training workout to support collection while the display sleeps. Raw sensors use Core Motion, with target 50 Hz sampling and real monotonic timestamps. The app must measure actual rates. Accelerations are in g and angular velocities in radians per second. The xArbitraryZVertical frame describes device attitude; raw vector channels remain in device axes.

The phone imports transferred recording files, reviews labels and exports original JSON. Corrections must preserve the original recording. No backend, accounts, model inference or automatic recognition is implemented in Run 1.

## API references

- [Apple watchOS project setup](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project)
- [Core Motion device updates](https://developer.apple.com/documentation/coremotion/cmmotionmanager/startdevicemotionupdates(using:to:withhandler:))
- [HealthKit workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
- [WatchConnectivity file transfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:))
- [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md)

Apple requires paired physical devices for WatchConnectivity file transfer testing. Simulator compilation is a separate gate from device reliability.

## Native UI validation

`./scripts/test-ui.sh ios [simulator-UUID]` and `./scripts/test-ui.sh watch [simulator-UUID]` run native XCUITest on a dedicated simulator. If the UUID is omitted, the script selects an available iPhone or Watch simulator. Tests use explicit DEBUG-and-simulator-only launch flags, visibly synthetic device/participant identities, isolated `LIFTR-UI-Tests` storage and disabled test transport. These paths are absent from Release and physical-device builds. They verify UI, persistence, errors and exports; they do not validate real motion, HealthKit authorization, background behavior or paired delivery.

The phone existing-archive upgrade method requires a separately restored, synthetic prior-version app archive and is excluded by the routine script. Portable SQLite tests exercise migration, rollback and reopen automatically. The upgrade QA procedure also runs that native method against the actual synthetic files exported by the earlier app build.

[Apple Watch UI test setup](https://developer.apple.com/documentation/watchos-apps/setting-up-tests-for-your-watchos-app) describes the supported native runner. [File transfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)) and [user-info transfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)) require physical-device validation; activation and successful local import precede acknowledgement.

CI retains Xcode 26.2/macOS 15 for package and application builds, and uses Xcode 26.4.1/macOS 26 for native UI checks, matching the executed local UI toolchain. The [hosted image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) lists that Xcode and its 26.4 runtimes. The UI script chooses a runtime matching the selected SDK rather than an arbitrary newer installed runtime.
