#!/usr/bin/env bash
#
# Build Graftbench.app — a real, double-clickable macOS application bundle.
#
#   Scripts/build_app.sh            # build dist/Graftbench.app
#   Scripts/build_app.sh --install  # also copy it into /Applications
#   Scripts/build_app.sh --run      # build, then launch it
#
set -euo pipefail

CONFIG=release
APP_NAME=Graftbench
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Copy SwiftPM resource bundles (Bundle.module) so brand images resolve.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
if [ -f "$ROOT/Packaging/AppIcon.icns" ]; then
    cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Embed the Sparkle framework (auto-update). SPM links it from an absolute path
# under .build that won't exist on other Macs, so copy the framework into the
# bundle and add a portable rpath — without this a downloaded .app can't launch.
SPARKLE_FW="$(/usr/bin/find "$ROOT/.build" -type d -name 'Sparkle.framework' -path '*macos*' 2>/dev/null | head -1)"
[ -z "$SPARKLE_FW" ] && SPARKLE_FW="$(/usr/bin/find "$ROOT/.build" -type d -name 'Sparkle.framework' 2>/dev/null | head -1)"
if [ -n "$SPARKLE_FW" ]; then
    echo "▸ Embedding Sparkle.framework…"
    mkdir -p "$APP/Contents/Frameworks"
    rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
else
    echo "  ⚠︎ Sparkle.framework not found under .build — auto-update will be disabled in this bundle."
fi

echo "▸ Ad-hoc code signing…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built $APP"

for arg in "$@"; do
    case "$arg" in
        --install)
            DEST="/Applications/$APP_NAME.app"
            echo "▸ Installing to $DEST…"
            rm -rf "$DEST"
            cp -R "$APP" "$DEST"
            echo "✓ Installed to $DEST"
            ;;
        --run)
            echo "▸ Launching…"
            open "$APP"
            ;;
    esac
done
