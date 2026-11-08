#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test
LIFTR_PYTHON_BIN="${LIFTR_PYTHON:-python3.13}"
"$LIFTR_PYTHON_BIN" -m unittest discover -s tests/python -v
swift run liftr-schema-fixture .build/synthetic-schema.liftr.json
"$LIFTR_PYTHON_BIN" ml/validation/validate_recording.py .build/synthetic-schema.liftr.json --json
