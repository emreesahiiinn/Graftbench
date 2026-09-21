#!/usr/bin/env bash
#
# Build Graftbench.app and package it into a distributable .dmg.
#
#   Scripts/package_dmg.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME=Graftbench
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

"$ROOT/Scripts/build_app.sh"

echo "▸ Creating DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✓ $DMG"
echo "  To distribute outside your Mac, sign + notarize it — see Packaging/NOTARIZE.md"
