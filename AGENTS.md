# LIFTR engineering rules

LIFTR is a private personal native SwiftUI watchOS and iOS project. Keep recordings, health data, credentials and signing files out of Git. Use the supplied LIFTR v2 product specification as the product authority.

Use feature branches and pull requests. Keep main buildable. Use one writer for shared package and project files. Separate worker worktrees, disjoint ownership, explicit shared contracts. Do not publish or deploy without user authorization.

Run 1 is labelled data collection only. Never invent model accuracy, real motion recordings, physical-device results or successful builds. Report written, compiled, tested, simulated and physically tested evidence separately.

Preserve stable exercise IDs and recording UUIDs. Raw motion uses Core Motion device coordinates, acceleration in g, rotation rate in rad/s and monotonic seconds since boot. Wall-clock dates use ISO 8601. Schema changes need validator and tests.

Use explicit DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer when the default selection points to CommandLineTools. No global developer-directory or signing changes are necessary.
