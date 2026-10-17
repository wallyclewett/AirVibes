#!/bin/bash
# Builds a universal AirVibes.app (ad-hoc signed) and zips it into mac/build/.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AirVibes"
APP=build/AirVibes.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AirVibes"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
(cd build && ditto -c -k --keepParent AirVibes.app AirVibes-mac.zip)
echo "Built $APP"
