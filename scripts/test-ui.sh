#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LIFTR_UI_PLATFORM="${1:-ios}"
LIFTR_UI_UDID="${2:-}"
case "$LIFTR_UI_PLATFORM" in
  ios) LIFTR_UI_SCHEME=LIFTRPhoneUITests; LIFTR_UI_DEST='iOS Simulator'; LIFTR_UI_KIND=iOS ;;
  watch) LIFTR_UI_SCHEME=LIFTRWatchUITests; LIFTR_UI_DEST='watchOS Simulator'; LIFTR_UI_KIND=watchOS ;;
  *) echo 'Usage: scripts/test-ui.sh ios|watch [dedicated-simulator-UUID]' >&2; exit 2 ;;
esac
xcodebuild -version
mkdir -p .build/ui/results
if [[ -z "$LIFTR_UI_UDID" ]]; then
  if [[ "$LIFTR_UI_PLATFORM" == ios ]]; then LIFTR_UI_SDK=iphonesimulator; else LIFTR_UI_SDK=watchsimulator; fi
  LIFTR_UI_OS_VERSION="$(xcrun --sdk "$LIFTR_UI_SDK" --show-sdk-version)"
  xcrun simctl list devices available -j > .build/ui/available-devices.json
  LIFTR_UI_UDID="$("${LIFTR_PYTHON:-python3.13}" -c '
import json,sys
kind=sys.argv[1]
version="-".join(sys.argv[2].split(".")[:2])
data=json.load(open(".build/ui/available-devices.json"))
for runtime,devices in sorted(data["devices"].items(),reverse=True):
    if not runtime.endswith("."+kind+"-"+version): continue
    for device in devices:
        if device.get("isAvailable") and ((kind=="watchOS" and "Watch" in device["name"]) or (kind=="iOS" and "iPhone" in device["name"])):
            print("Selected "+runtime+" / "+device["name"],file=sys.stderr)
            print(device["udid"]); sys.exit(0)
sys.exit("No available matching simulator. Install its runtime in Xcode first.")
' "$LIFTR_UI_KIND" "$LIFTR_UI_OS_VERSION")"
fi
# The tests reset only their explicit LIFTR-UI-Tests sandbox on this simulator.
# The existing-archive upgrade method is a separate manual QA case: restore the
# prior-version synthetic archive before running that method with -only-testing.
LIFTR_UI_EXTRA=("-only-testing:$LIFTR_UI_SCHEME")
if [[ "$LIFTR_UI_PLATFORM" == ios ]]; then
  LIFTR_UI_EXTRA+=('-skip-testing:LIFTRPhoneUITests/LIFTRPhoneUITests/testExistingLegacyReviewMigratesWithoutChangingLabelsOrRaw')
fi
xcodebuild -project LIFTR.xcodeproj -scheme "$LIFTR_UI_SCHEME" \
  -destination "platform=$LIFTR_UI_DEST,id=$LIFTR_UI_UDID" \
  -derivedDataPath ".build/ui/$LIFTR_UI_PLATFORM" \
  -resultBundlePath ".build/ui/results/$LIFTR_UI_PLATFORM-$(date +%s).xcresult" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 120 CODE_SIGNING_ALLOWED=NO \
  "${LIFTR_UI_EXTRA[@]}" test
