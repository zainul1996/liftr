#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate
xcodebuild -project LIFTR.xcodeproj -scheme LIFTR -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode-ios CODE_SIGNING_ALLOWED=NO build
