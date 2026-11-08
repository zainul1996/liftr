# Build, install and test on your devices

Use a separate macOS user on the family MacBook. Sign into Xcode with your own Apple Account. There is no need to change the family member's iCloud account.

## Mac prerequisites

- A Mac running a version of macOS compatible with the installed Xcode.
- Xcode with the iOS and watchOS platforms installed. This project currently targets iOS 17 and watchOS 10 or later.
- XcodeGen 2.44 or later, Git, and Python 3.13.
- Your own GitHub account with access to the private `zainul1996/liftr` repository.
- A paired iPhone and Apple Watch with Developer Mode enabled when Xcode requests it.

The project was initially generated with Xcode 26.4.1. A compatible simulator build does not verify signing or physical-device behaviour.

Install Xcode from Apple, open it once, accept its licence and let required components install. If you use Homebrew, install prerequisites with `brew install xcodegen python@3.13 gh`. Authentication to GitHub and Apple is your action. Never paste credentials into the repository or send them to Codex.

## Clone and generate

```sh
gh repo clone zainul1996/liftr
cd liftr
./scripts/bootstrap.sh
open LIFTR.xcodeproj
```

The bootstrap script generates the Xcode project and creates a Python virtual environment. Xcode project generation uses `project.yml`. The Swift packages need no third-party download.

If the command-line tools point at the small CommandLineTools installation, use the explicit environment variable below for terminal builds. This does not change the Mac's global developer directory.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
./scripts/test.sh
./scripts/build-ios.sh
./scripts/build-watch.sh
```

The build scripts disable code signing for simulator builds. They do not install on your devices or publish anything.

## Signing and installing

1. In Xcode, open **Settings > Accounts** and add your Apple Account.
2. Open the project settings. For both `LIFTR` and `LIFTRWatch`, choose **Signing & Capabilities**, enable automatic signing and select your team.
3. Use unique bundle identifiers owned by your team if Xcode reports a conflict. Update the identifiers in `project.yml` together, including the watch companion bundle identifier, before generating again. Keep the watch identifier prefixed by the iPhone identifier.
4. Confirm the Watch target has the HealthKit entitlement and workout-processing background mode.
5. Connect and trust your iPhone. Keep its paired Watch nearby, unlocked and available to Xcode. Enable Developer Mode on both devices if requested.
6. Choose scheme `LIFTR`, choose your physical iPhone, and run. The phone target embeds the Watch app.
7. Choose scheme `LIFTRWatch`, select your paired Apple Watch, and run if the Watch app did not install automatically.
8. Open the apps on both devices. Grant workout and motion permissions when asked.

A free Personal Team can be useful for device development. Apple's current watchOS capability table includes HealthKit for free developer accounts, but your actual provisioning profile still needs to resolve successfully in Xcode. Free provisioning has expiry limits, so be prepared to rebuild. TestFlight and App Store distribution require the appropriate paid program membership. No physical signing was performed by the implementation agents.

References: [Apple's developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/), [watchOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-watchos/), [HealthKit configuration](https://developer.apple.com/documentation/xcode/configuring-healthkit-access), and [run on a device](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html).

## First physical smoke test

1. Start a short workout and record one 10 to 20 second set. Enter an easily checked rep count and weight, then save.
2. Return to rest and record a second set of the same exercise. Confirm you did not need to reselect it.
3. Check the phone receives both recordings. Open each recording and inspect the sample count and actual rate.
4. Change reps or weight on the phone, export, and confirm the export includes current labels, originals and review history.
5. Validate the export on the Mac. Reopen both apps and verify the recordings persist.

WatchConnectivity's `transferFile` is not supported by Simulator. Apple explicitly requires paired-device testing for it. Simulator launch and UI screenshots cannot establish transfer success. See [Apple's transferFile documentation](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)).

## Interruption and offline checks

Record the result and any failure rather than marking the list passed in advance.

| Test | Expected evidence |
| --- | --- |
| Lower wrist and let screen sleep during a set | Samples continue through the set, verified in exported timestamps |
| Disconnect iPhone during capture | Recording saves on Watch, then arrives when devices reconnect |
| Record several sets while phone is unavailable | Separate stable UUIDs, no lost or duplicate visible recordings |
| Close and reopen iPhone app | Received recordings and reviews remain |
| Retry transfer of an existing set | Stable UUID imports once |
| Decline a permission | Clear message and no false recording success |
| End workout or trigger a system interruption | No unnoticed capture after the intended lifecycle ends |
| Storage or write failure | Error reported, original/partial data retained when possible |
| Delete a phone recording | Phone copy disappears, scope of deletion is clear |
| 60 to 90 minute session | Record actual battery change, thermal issues and delivery delays |

Continuous capture and recovery are implemented and covered with synthetic automated checks. Real-device background capture, interruption recovery and long-session battery reliability remain physical test gates. Do not use an unfinished feature as the only copy of an important dataset.

## Later updates

From the repository's stable branch, pull the latest reviewed changes, regenerate with the bootstrap script and run on the same devices again. Project regeneration uses `project.yml` and can reset generated signing values; reselect your team in Xcode before physical-device installation. Do not discard your local signing settings or raw data to resolve a Git conflict. Ask for help and preserve the files first.

## Delivery and acknowledgement checks

WatchConnectivity file transfer and user-info delivery do not work in Simulator. On paired physical devices, record with the phone disconnected, relaunch Watch and verify local persistence, then reconnect. Verify the same UUID imports once, acknowledgement survives Watch relaunch, and Retry does not duplicate it. A failed iPhone import must not acknowledge success; a later retry must recover. Cancelling a queued transfer before Watch deletion cannot erase already delivered phone copies.

References: [file transfer](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)) and [user-info transfer](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)).
