#!/bin/sh
# Packages dist/macrecord.app into dist/macrecord.dmg (drag-to-Applications layout).
set -eu
cd "$(dirname "$0")/.."
[ -d dist/macrecord.app ] || ./scripts/build-app.sh
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/macrecord.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/macrecord.dmg
hdiutil create -volname macrecord -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet dist/macrecord.dmg
hdiutil verify -quiet dist/macrecord.dmg
echo "Built dist/macrecord.dmg ($(du -h dist/macrecord.dmg | cut -f1 | tr -d ' '))"
