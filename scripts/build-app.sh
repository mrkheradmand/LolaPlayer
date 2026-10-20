#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift -module-cache-path "$PWD/.build/module-cache" scripts/generate-icon.swift Resources/LolaPlayerIcon.png Resources/AppIcon.icns
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release -debug-info-format none
APP="$PWD/dist/Lola Player.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp .build/release/LolaPlayer "$APP/Contents/MacOS/LolaPlayer"
python3 scripts/bundle-runtime.py "$APP"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/WelcomeNature.png "$APP/Contents/Resources/WelcomeNature.png"
cp Resources/AppIcon.icns "$APP/Contents/Resources/LolaPlayerIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
