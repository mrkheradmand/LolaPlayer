#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/dist/Lola Player.app"
python3 scripts/version.py check
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
FILENAME="LolaPlayer-$VERSION-macOS-arm64.dmg"
RELEASES="$PWD/dist/releases"
STAGE="$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")"
MOUNTED=0
cleanup() {
    if (( MOUNTED )); then hdiutil detach "$STAGE/verify" >/dev/null || return; fi
    rm -rf "$STAGE"
}
trap cleanup EXIT
mkdir "$STAGE/content"
ditto "$APP" "$STAGE/content/Lola Player.app"
ln -s /Applications "$STAGE/content/Applications"
cp "$PWD/Resources/Install Notes.txt" "$STAGE/content/Install Notes.txt"
mkdir -p "$RELEASES"
# APFS preserves signed bundle metadata; makehybrid's HFS catalog synthesizes
# FinderInfo on nested libraries and invalidates strict signature verification.
hdiutil create -volname "Lola Player $VERSION" -srcfolder "$STAGE/content" -fs APFS -format ULMO "$STAGE/$FILENAME"
hdiutil verify "$STAGE/$FILENAME"
mkdir "$STAGE/verify"
hdiutil attach -readonly -nobrowse -mountpoint "$STAGE/verify" "$STAGE/$FILENAME"
MOUNTED=1
codesign --verify --deep --strict "$STAGE/verify/Lola Player.app"
hdiutil detach "$STAGE/verify"
MOUNTED=0
(
    cd "$STAGE"
    shasum -a 256 "$FILENAME" > SHA256SUMS.txt
)
# Archive previous releases only after the replacement has passed verification.
for PREVIOUS in "$RELEASES"/LolaPlayer*.dmg(N); do
    [[ "${PREVIOUS:t}" == "$FILENAME" ]] && continue
    ARCHIVE="$RELEASES/old"
    mkdir -p "$ARCHIVE"
    if [[ -e "$ARCHIVE/${PREVIOUS:t}" ]]; then
        ARCHIVE="$(mktemp -d "$ARCHIVE/duplicate.XXXXXX")"
    fi
    mv "$PREVIOUS" "$ARCHIVE/"
    (
        cd "$ARCHIVE"
        shasum -a 256 "${PREVIOUS:t}" > "${PREVIOUS:t}.sha256"
    )
done
mv "$STAGE/$FILENAME" "$RELEASES/$FILENAME"
cp "$STAGE/SHA256SUMS.txt" "$RELEASES/SHA256SUMS.txt"
echo "Created dist/releases/$FILENAME"
