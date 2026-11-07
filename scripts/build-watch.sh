#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate
xcodebuild -project LIFTR.xcodeproj -scheme LIFTRWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' -derivedDataPath .build/xcode-watch CODE_SIGNING_ALLOWED=NO build
