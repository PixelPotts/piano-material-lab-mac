#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Piano Material Lab.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun clang -O2 -Wall -Wextra -Wno-unused-function -Wno-unused-parameter \
  -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
  macos/Piano.m -framework Cocoa -framework AudioToolbox \
  -o "$APP/Contents/MacOS/PianoMaterialLab"
cp macos/Info.plist "$APP/Contents/Info.plist"
cp MODEL.txt CONTROL-GUIDE.txt MAC-VALIDATION.txt "$APP/Contents/Resources/"
cp README.md "$APP/Contents/Resources/README.txt"
xcrun clang -O2 -Wno-unused-function -arch arm64 -arch x86_64 \
  -mmacosx-version-min=11.0 synth-cli.c -o build/synth-cli
xcrun clang -O2 -Wno-unused-function -arch arm64 -arch x86_64 \
  -mmacosx-version-min=11.0 engine-validation.c -o build/engine-validation
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/PianoMaterialLab"
ditto -c -k --sequesterRsrc --keepParent "$APP" build/Piano-Material-Lab-macOS-universal.zip
echo "Built universal Mac app: $APP"
