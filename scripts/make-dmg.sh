#!/usr/bin/env bash
# Build a release Loft Hours.app and package it into a distributable .dmg.
# This is the AD-HOC path: the app is ad-hoc signed (no Apple Developer ID), so
# the DMG is NOT notarized. Recipients must bypass Gatekeeper once (right-click
# Open, or System Settings > Privacy & Security > Open Anyway). Notarization
# comes with a paid Developer ID in the Phase 5 plan.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Build a release bundle (also ad-hoc signs the .app).
"$ROOT/scripts/build-app.sh" release

APP="$ROOT/Loft Hours.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
VOL_NAME="Loft Hours $VERSION beta"

OUT="$ROOT/dist"
mkdir -p "$OUT"
DMG_PATH="$OUT/Loft-Hours-$VERSION-beta.dmg"
rm -f "$DMG_PATH"

# Stage the .app plus an /Applications symlink so users can drag-to-install.
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Bundle a plain-text install guide so first-time openers know the Gatekeeper
# steps for an un-notarized build.
cat > "$STAGING/INSTALL.txt" <<TXT
Loft Hours $VERSION (beta)

INSTALL
1. Drag "Loft Hours" onto the Applications folder in this window.

FIRST LAUNCH (one time only)
This beta is not notarized by Apple, so macOS will warn that it is from an
unidentified developer the first time you open it. To get past that:

  - Open your Applications folder, right-click "Loft Hours", and choose Open.
    In the dialog that appears, click Open again.

  - If you do not see an Open option (macOS 15 Sequoia and later):
    open System Settings > Privacy & Security, scroll to the bottom, and
    click "Open Anyway" next to the Loft Hours message. Then launch it again.

After this one time, Loft Hours opens normally like any other app.

REQUIREMENTS
  - macOS 14 (Sonoma) or later
  - Apple Silicon Mac (M1/M2/M3/M4). This build does not run on Intel Macs.

KNOWN ISSUES (beta)
  - The app icon may appear blank on the left of system notifications. This is
    a side effect of the build not being signed yet and does not affect the app.
TXT

# Bundle the project README and LICENSE so the DMG is self-documenting.
# README.md references docs/logo.png, so copy that alongside it (in a docs/
# subfolder) so the logo still resolves in a Markdown viewer.
cp "$ROOT/README.md" "$STAGING/README.md"
cp "$ROOT/LICENSE" "$STAGING/LICENSE.txt"
mkdir -p "$STAGING/docs"
cp "$ROOT/docs/logo.png" "$STAGING/docs/logo.png"

# Strip the quarantine flag from the staged copy so the DMG itself is clean
# (the download still re-applies quarantine on the recipient's machine).
xattr -dr com.apple.quarantine "$STAGING/Loft Hours.app" 2>/dev/null || true

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

echo "DMG: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
