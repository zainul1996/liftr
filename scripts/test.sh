#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test
python3 -m unittest discover -s tests/python -v
swift run liftr-schema-fixture .build/synthetic-schema.liftr.json
python3 ml/validation/validate_recording.py .build/synthetic-schema.liftr.json --json
