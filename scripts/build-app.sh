#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
python3 scripts/version.py check
python3 scripts/sync-formats.py --check
swift -module-cache-path "$PWD/.build/module-cache" scripts/generate-icon.swift Resources/LolaPlayerIcon.png Resources/AppIcon.icns
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release -debug-info-format none
STAGE="$(mktemp -d "$PWD/.build/app-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Lola Player.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp .build/release/LolaPlayer "$APP/Contents/MacOS/LolaPlayer"
python3 scripts/bundle-runtime.py "$APP"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/WelcomeNature.png "$APP/Contents/Resources/WelcomeNature.png"
cp Resources/AppIcon.icns "$APP/Contents/Resources/LolaPlayerIcon.icns"
cp versions.md "$APP/Contents/Resources/versions.md"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
FINAL="$PWD/dist/Lola Player.app"
mkdir -p "$PWD/dist"
if [[ -d "$FINAL" ]]; then
    PREVIOUS="$(mktemp -d "$PWD/.build/app-previous.XXXXXX")"
    mv "$FINAL" "$PREVIOUS/Lola Player.app"
fi
mv "$APP" "$FINAL"
echo "Built: $FINAL"
