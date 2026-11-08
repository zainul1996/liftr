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
import json,os,subprocess,sys
kind=sys.argv[1]
version="-".join(sys.argv[2].split(".")[:2])
data=json.load(open(".build/ui/available-devices.json"))
for runtime,devices in sorted(data["devices"].items(),reverse=True):
    if not runtime.endswith("."+kind+"-"+version): continue
    preferred="Apple Watch Series 11 (46mm)" if kind=="watchOS" else "iPhone 17 Pro"
    for device in sorted(devices,key=lambda d:d["name"]!=preferred):
        if device.get("isAvailable") and ((kind=="watchOS" and "Watch" in device["name"]) or (kind=="iOS" and "iPhone" in device["name"])):
            print("Selected "+runtime+" / "+device["name"],file=sys.stderr)
            if os.environ.get("LIFTR_UI_FRESH_SIMULATOR")=="1":
                created=subprocess.run(["xcrun","simctl","create","LIFTR UI "+kind,device["deviceTypeIdentifier"],runtime],check=True,capture_output=True,text=True,timeout=30)
                print(created.stdout.strip())
            else:
                print(device["udid"])
            sys.exit(0)
sys.exit("No available matching simulator. Install its runtime in Xcode first.")
' "$LIFTR_UI_KIND" "$LIFTR_UI_OS_VERSION")"
fi
# Match the explicit prebooted-device setup used by local native UI QA.
"${LIFTR_PYTHON:-python3.13}" - "$LIFTR_UI_UDID" <<'PYBOOT'
import subprocess,sys
process=subprocess.Popen(["xcrun","simctl","bootstatus",sys.argv[1],"-b"])
for elapsed in (30,60,90):
    try:
        result=process.wait(timeout=30)
        if result: raise SystemExit(result)
        break
    except subprocess.TimeoutExpired:
        print("Simulator readiness still pending after "+str(elapsed)+"s of a 90s budget",flush=True)
else:
    process.kill()
    process.wait(timeout=10)
    raise SystemExit("Simulator did not finish booting within 90s; native tests were not started")
PYBOOT
# The tests reset only their explicit LIFTR-UI-Tests sandbox on this simulator.
# The existing-archive upgrade method is a separate manual QA case: restore the
# prior-version synthetic archive before running that method with -only-testing.
LIFTR_UI_EXTRA=("-only-testing:$LIFTR_UI_SCHEME")
if [[ "$LIFTR_UI_PLATFORM" == ios ]]; then
  LIFTR_UI_EXTRA+=('-skip-testing:LIFTRPhoneUITests/LIFTRPhoneUITests/testExistingLegacyReviewMigratesWithoutChangingLabelsOrRaw')
fi
if xcodebuild -project LIFTR.xcodeproj -scheme "$LIFTR_UI_SCHEME" \
  -destination "platform=$LIFTR_UI_DEST,id=$LIFTR_UI_UDID" \
  -derivedDataPath ".build/ui/$LIFTR_UI_PLATFORM" \
  -resultBundlePath ".build/ui/results/$LIFTR_UI_PLATFORM-$(date +%s).xcresult" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 120 CODE_SIGNING_ALLOWED=NO \
  "${LIFTR_UI_EXTRA[@]}" test; then
  exit 0
else
  LIFTR_UI_TEST_STATUS=$?
  "${LIFTR_PYTHON:-python3.13}" - "$LIFTR_UI_UDID" "$LIFTR_UI_PLATFORM" <<'PYDIAG' || true
import subprocess,sys
bundles=("com.zainul.liftr.watchkitapp","com.zainul.liftr.watch-uitests.xctrunner") if sys.argv[2]=="watch" else ("com.zainul.liftr","com.zainul.liftr.phone-uitests.xctrunner")
for bundle in bundles:
    try:
        result=subprocess.run(["xcrun","simctl","get_app_container",sys.argv[1],bundle,"app"],capture_output=True,text=True,timeout=10)
        print(bundle+": "+("app container found" if result.returncode==0 else "app container unavailable"))
    except subprocess.TimeoutExpired:
        print(bundle+": app-container lookup timed out")
PYDIAG
  exit "$LIFTR_UI_TEST_STATUS"
fi
