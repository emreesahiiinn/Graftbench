#!/usr/bin/env bash
#
# Rasterize the brand SVGs into:
#   • Packaging/AppIcon.icns        (Dock / app icon)
#   • Sources/.../Resources/*.png   (in-app wordmark + mark)
#
# Expects BrandAssets/graftbench-icon.svg and BrandAssets/graftbench-logo.svg.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAND="$ROOT/BrandAssets"
RES="$ROOT/Sources/Graftbench/Resources"
PKG="$ROOT/Packaging"
TMP="$(mktemp -d)"

ICON_SVG="$BRAND/graftbench-icon.svg"
LOGO_SVG="$BRAND/graftbench-logo.svg"

for f in "$ICON_SVG" "$LOGO_SVG"; do
    [ -f "$f" ] || { echo "✗ missing $f — copy the SVGs into $BRAND first"; exit 1; }
done

RASTER="$TMP/raster.swift"
cat > "$RASTER" <<'EOF'
import AppKit
let a = CommandLine.arguments
guard a.count >= 5, let w = Double(a[3]), let h = Double(a[4]) else { exit(2) }
guard let img = NSImage(contentsOf: URL(fileURLWithPath: a[1])) else { FileHandle.standardError.write("nil image\n".data(using:.utf8)!); exit(1) }
let out = NSImage(size: NSSize(width: w, height: h))
out.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
img.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
out.unlockFocus()
guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: a[2]))
EOF

raster() { swift "$RASTER" "$1" "$2" "$3" "$4"; }

echo "▸ Building AppIcon.iconset…"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
raster "$ICON_SVG" "$ICONSET/icon_16x16.png"      16   16
raster "$ICON_SVG" "$ICONSET/icon_16x16@2x.png"   32   32
raster "$ICON_SVG" "$ICONSET/icon_32x32.png"      32   32
raster "$ICON_SVG" "$ICONSET/icon_32x32@2x.png"   64   64
raster "$ICON_SVG" "$ICONSET/icon_128x128.png"    128  128
raster "$ICON_SVG" "$ICONSET/icon_128x128@2x.png" 256  256
raster "$ICON_SVG" "$ICONSET/icon_256x256.png"    256  256
raster "$ICON_SVG" "$ICONSET/icon_256x256@2x.png" 512  512
raster "$ICON_SVG" "$ICONSET/icon_512x512.png"    512  512
raster "$ICON_SVG" "$ICONSET/icon_512x512@2x.png" 1024 1024

mkdir -p "$PKG"
iconutil -c icns "$ICONSET" -o "$PKG/AppIcon.icns"
echo "✓ $PKG/AppIcon.icns"

echo "▸ Rendering in-app PNGs…"
mkdir -p "$RES"
raster "$ICON_SVG" "$RES/BrandMark.png"     512 512
raster "$ICON_SVG" "$RES/BrandMark@2x.png"  512 512
raster "$LOGO_SVG" "$RES/BrandWordmark.png" 1600 420
echo "✓ $RES/BrandMark.png + BrandWordmark.png"

rm -rf "$TMP"
echo "Done."
