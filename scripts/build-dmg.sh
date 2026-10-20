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
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/content"
ditto "$APP" "$STAGE/content/Lola Player.app"
ln -s /Applications "$STAGE/content/Applications"
cp "$PWD/Resources/Install Notes.txt" "$STAGE/content/Install Notes.txt"
mkdir -p "$RELEASES"
# Build HFS+ in userspace, then compress; no writable disk-image mount required.
hdiutil makehybrid -hfs -hfs-volume-name "Lola Player $VERSION" -o "$STAGE/source.dmg" "$STAGE/content"
hdiutil convert "$STAGE/source.dmg" -format ULMO -o "$STAGE/$FILENAME"
hdiutil verify "$STAGE/$FILENAME"
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
