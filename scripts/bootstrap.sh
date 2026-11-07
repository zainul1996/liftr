#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
command -v xcodegen >/dev/null || { echo 'Install XcodeGen with: brew install xcodegen'; exit 1; }
xcodebuild -version
xcodegen generate
python3 -m venv .venv
echo 'Project generated. See docs/device-testing.md for signing and installation.'
