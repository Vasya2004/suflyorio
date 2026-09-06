#!/bin/bash
set -euo pipefail
SUFLER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SUFLER_ROOT"
python3 scripts/check_core.py
python3 scripts/validate_project.py

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcodebuild -version > /dev/null 2>&1; then
  echo "INCOMPLETE: install full Xcode with iOS platform support. Core checks passed; iOS compilation and device tests remain unverified."
  exit 2
fi
mkdir -p .build/verification
xcodebuild -project Sufler.xcodeproj -scheme Sufler -destination 'generic/platform=iOS' \
  -derivedDataPath .build/verification/DerivedData CODE_SIGNING_ALLOWED=NO build > .build/verification/ios-build.log 2>&1 || {
    tail -n 80 .build/verification/ios-build.log
    exit 1
  }
SUFLER_SIMULATOR="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((v["udid"] for runtime,vs in d["devices"].items() if "iOS-26" in runtime for v in vs if v["name"].startswith("iPhone") and v.get("isAvailable")), ""))')"
if [[ -z "$SUFLER_SIMULATOR" ]]; then
  echo "INCOMPLETE: iOS build passed; install an iOS 26 simulator in Xcode to run automated storage tests."
  exit 2
fi
xcodebuild -project Sufler.xcodeproj -scheme Sufler -destination "platform=iOS Simulator,id=$SUFLER_SIMULATOR" \
  -derivedDataPath .build/verification/DerivedData CODE_SIGNING_ALLOWED=NO test > .build/verification/ios-tests.log 2>&1 || {
    tail -n 100 .build/verification/ios-tests.log
    exit 1
  }
echo "PASS: iOS build and simulator tests. Physical camera acceptance is still required: docs/DEVICE_CHECKLIST.md"
