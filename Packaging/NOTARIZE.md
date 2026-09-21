# Signing, Notarizing & Distributing Graftbench

The build scripts produce an **ad-hoc–signed** `Graftbench.app`, which runs fine
on the Mac that built it. To ship it to other Macs without Gatekeeper warnings you
need an Apple **Developer ID** certificate (a paid Apple Developer account) and
must sign + notarize. These steps require your own credentials, so run them
yourself.

## 1. Sign with Developer ID

```bash
# Find your identity:
security find-identity -v -p codesigning

# Sign the app (hardened runtime is required for notarization):
codesign --deep --force --options runtime --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  dist/Graftbench.app

# Verify:
codesign --verify --deep --strict --verbose=2 dist/Graftbench.app
```

## 2. Package a DMG

```bash
Scripts/package_dmg.sh
```

## 3. Notarize (notarytool)

```bash
# One-time: store credentials in the keychain
xcrun notarytool store-credentials graftbench-notary \
  --apple-id "you@example.com" --team-id "TEAMID" --password "APP-SPECIFIC-PASSWORD"

# Submit and wait:
xcrun notarytool submit dist/Graftbench.dmg \
  --keychain-profile graftbench-notary --wait

# Staple the ticket:
xcrun stapler staple dist/Graftbench.dmg
```

## 4. Auto-update (optional, later)

For in-app auto-update, add the **Sparkle** package
(`https://github.com/sparkle-project/Sparkle`) to `Package.swift`, host an
`appcast.xml`, and sign updates with an EdDSA key. This needs a hosting location
and the signing keys, so it's left as a follow-up once distribution is set up.

## Notes

- The bundle identifier is `com.graftbench.Graftbench` (see `Packaging/Info.plist`).
- A custom app icon lives in `Packaging/AppIcon.icns` (regenerate with
  `Scripts/make_brand.sh`).
