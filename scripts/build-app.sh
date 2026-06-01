#!/usr/bin/env bash
# Build LoftHours and assemble a runnable Loft Hours.app bundle.
# Phase 1: unsigned, for local running. Signing + App Store packaging come with
# Xcode in Phase 5.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Build against the Command Line Tools toolchain. Full Xcode requires accepting
# its license (sudo xcodebuild -license) before its tools run; the CLT toolchain
# builds this SPM package without that step. Override by exporting DEVELOPER_DIR
# before calling this script if you'd rather use Xcode.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

CONFIG="${1:-debug}"   # debug | release
echo "Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/LoftHours"
APP="$ROOT/Loft Hours.app"

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LoftHours"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Bundle the Nunito font so ATSApplicationFontsPath (=Fonts) can register it at
# launch. Lives in Contents/Resources/Fonts.
if [ -d "$ROOT/Resources/Fonts" ]; then
  cp -R "$ROOT/Resources/Fonts" "$APP/Contents/Resources/Fonts"
fi

# Bundle the app icon so Finder and the Dock show it instead of the generic
# icon. Referenced by CFBundleIconFile=AppIcon in Info.plist.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Bundle runtime images (menu-bar icon, notification icon). Lives in
# Contents/Resources/Images; loaded by name at runtime via Bundle.main.
if [ -d "$ROOT/Resources/Images" ]; then
  cp -R "$ROOT/Resources/Images" "$APP/Contents/Resources/Images"
fi

# Bundle the ready-made Focus shortcuts so users can one-click install them
# instead of hand-building a Shortcut. Lives in Contents/Resources/Shortcuts.
if [ -d "$ROOT/Resources/Shortcuts" ]; then
  cp -R "$ROOT/Resources/Shortcuts" "$APP/Contents/Resources/Shortcuts"
fi

# Ad-hoc sign so macOS will launch it without Gatekeeper friction.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Done: $APP"
