# Run 1 architecture

The watch and iPhone apps share a local Swift package. LIFTRCore owns schema version 1 and the stable nine-exercise taxonomy. LIFTRPersistence stores canonical recordings under Application Support, using UUID filenames and atomic writes. LIFTRSync uses WatchConnectivity queued file transfers. LIFTRMotion collects and streams raw motion samples.

Each export is a standard UTF-8 JSON file with metadata, samples and annotations. A watch writer can append samples incrementally and add final metadata when the set finishes, so long recordings do not require one in-memory array. Metadata summaries let Watch list recordings without loading raw samples.

The watch starts a HealthKit strength-training workout to support collection while the display sleeps. Raw sensors use Core Motion, with target 50 Hz sampling and real monotonic timestamps. The app must measure actual rates. Accelerations are in g and angular velocities in radians per second. The xArbitraryZVertical frame describes device attitude; raw vector channels remain in device axes.

The phone imports transferred recording files, reviews labels and exports original JSON. Corrections must preserve the original recording. No backend, accounts, model inference or automatic recognition is implemented in Run 1.

## API references

- [Apple watchOS project setup](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project)
- [Core Motion device updates](https://developer.apple.com/documentation/coremotion/cmmotionmanager/startdevicemotionupdates(using:to:withhandler:))
- [HealthKit workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
- [WatchConnectivity file transfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:))
- [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md)

Apple requires paired physical devices for WatchConnectivity file transfer testing. Simulator compilation is a separate gate from device reliability.
