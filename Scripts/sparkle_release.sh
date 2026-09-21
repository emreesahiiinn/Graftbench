#!/usr/bin/env bash
#
# Cut a Sparkle-enabled Graftbench release — LOCAL FALLBACK.
#
# The normal path is CI: push a tag (e.g. v0.2.0) and .github/workflows/release.yml
# builds, signs and publishes everything. Use this script only to cut a release by
# hand (CI down, or a local test). It signs with your Keychain key.
#
#   Scripts/sparkle_release.sh 0.2.0
#
# ── One-time setup (once, ever) ───────────────────────────────────────────────
#   1. Run this script once with any version to download the Sparkle tools, or
#      fetch them yourself; then generate your signing keys:
#         .sparkle-tools/bin/generate_keys
#      It stores a PRIVATE EdDSA key in your login Keychain and prints a PUBLIC
#      key. Paste that public key into Packaging/Info.plist -> SUPublicEDKey.
#      (The private key never leaves your Mac.)
#
# ── Each release ──────────────────────────────────────────────────────────────
#   • Bump the version in Packaging/Info.plist (CFBundleShortVersionString +
#     CFBundleVersion) to match the version you pass here.
#   • This script builds dist/Graftbench.app + dist/Graftbench.dmg, signs the DMG
#     with your Keychain key, and (re)writes appcast.xml with the new <item>.
#   • Then publish the two things it prints: commit appcast.xml, and upload THIS
#     dist/Graftbench.dmg to the GitHub release for tag v<version>.
#
# The DMG Sparkle points at MUST be the exact file signed here, so upload
# dist/Graftbench.dmg to the release yourself rather than letting CI rebuild a
# different binary for that tag.
#
set -euo pipefail

VER="${1:?usage: Scripts/sparkle_release.sh <version, e.g. 0.2.0>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="emreesahiiinn/Graftbench"
SPARKLE_TOOLS_VER="2.6.4"
TOOLS="$ROOT/.sparkle-tools"
BIN="$TOOLS/bin"

# 1. Fetch the Sparkle CLI tools once (generate_keys / generate_appcast / sign_update).
if [ ! -x "$BIN/generate_appcast" ]; then
    echo "▸ Downloading Sparkle $SPARKLE_TOOLS_VER tools…"
    mkdir -p "$TOOLS"
    curl -fL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_TOOLS_VER/Sparkle-$SPARKLE_TOOLS_VER.tar.xz" \
        | tar -xJ -C "$TOOLS" bin
    echo "  tools in $BIN"
    echo "  If you have not made your signing key yet, run: $BIN/generate_keys"
fi

# 2. Sanity-check the bundle version matches the release version.
PLIST_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Packaging/Info.plist")"
if [ "$PLIST_VER" != "$VER" ]; then
    echo "✗ Packaging/Info.plist CFBundleShortVersionString is $PLIST_VER, expected $VER."
    echo "  Bump it (and CFBundleVersion) first so the appcast advertises the right version."
    exit 1
fi

# 3. Build the .app + .dmg.
"$ROOT/Scripts/package_dmg.sh"

# 4. Stage the DMG and (re)generate the signed appcast.
UPDATES="$ROOT/dist/updates"
mkdir -p "$UPDATES"
cp -f "$ROOT/dist/Graftbench.dmg" "$UPDATES/"

echo "▸ Signing + generating appcast…"
"$BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VER/" \
    --link "https://github.com/$REPO" \
    -o "$ROOT/dist/appcast.xml" \
    "$UPDATES"

echo
echo "✓ dist/appcast.xml generated for v$VER"
echo "Publish it — create the GitHub release for tag v$VER and upload BOTH:"
echo "       $ROOT/dist/Graftbench.dmg"
echo "       $ROOT/dist/appcast.xml"
echo "  (SUFeedURL points at releases/latest/download/appcast.xml, so the feed"
echo "   must be attached to the release, not committed to the repo.)"
echo "  Optional: update Casks/graftbench.rb version+sha256 for Homebrew users."
