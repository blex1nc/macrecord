#!/bin/sh
# Builds dist/macrecord.app (universal: arm64 + x86_64) and signs it.
#   VERSION=1.0.0 ./scripts/build-app.sh
#   SIGN_IDENTITY="macrecord dev" ./scripts/build-app.sh   # stable identity keeps TCC permissions across builds
set -eu
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS="${ARCHS:-arm64 x86_64}"
APP=dist/macrecord.app

ARCH_FLAGS=""
for arch in $ARCHS; do ARCH_FLAGS="$ARCH_FLAGS --arch $arch"; done
# shellcheck disable=SC2086
swift build -c release --product macrecord $ARCH_FLAGS
BIN_DIR=$(swift build -c release --product macrecord $ARCH_FLAGS --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/macrecord" "$APP/Contents/MacOS/macrecord"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" App/Info.plist > "$APP/Contents/Info.plist"
cp -R App/Resources/*.lproj "$APP/Contents/Resources/"
[ -f App/AppIcon.icns ] && cp App/AppIcon.icns "$APP/Contents/Resources/" && \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"

# Ad-hoc ("-") unless a real identity is given. Hardened runtime; no entitlements are needed.
# macOS ties Accessibility / Input Monitoring grants to the designated requirement. For ad-hoc signatures that is
# the cdhash, which changes on every build, so grants silently stop matching. Local ad-hoc builds therefore use an
# identifier-based requirement so permissions survive rebuilds. Releases (RELEASE=1) keep the strict cdhash
# requirement: an identifier-only requirement would let any app using this identifier inherit the grants.
if [ "$SIGN_IDENTITY" = "-" ] && [ "${RELEASE:-0}" != "1" ]; then
    codesign --force --options runtime --timestamp=none --sign - \
        -r='designated => identifier "io.github.blex1nc.macrecord"' "$APP"
else
    codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/macrecord"))"
