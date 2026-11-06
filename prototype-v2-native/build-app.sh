#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
app="dist/Audio Lab.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/AudioPrototype "$app/Contents/MacOS/AudioPrototype"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built: $PWD/$app"
