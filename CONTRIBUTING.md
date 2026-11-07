# Contributing

Use Swift 6, Xcode 26 and XcodeGen 2.44 or later. Work on a feature branch and open a private pull request. Run `./scripts/test.sh`, `./scripts/build-ios.sh` and `./scripts/build-watch.sh` before requesting review.

Do not add raw recordings, datasets, health exports, signing assets or credentials. Tests may create clearly identified synthetic samples in temporary directories. A simulator build cannot verify Core Motion sampling, workout background execution, battery use or WatchConnectivity file delivery.

Keep raw samples immutable. Record corrections separately. Preserve exercise IDs across display name changes. Do not add production model weights until they are trained using approved real Apple Watch recordings and evaluated by held-out session.
