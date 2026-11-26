#!/usr/bin/env zsh
set -euo pipefail

# TouchBarLyrics — reproducible local build (direct swiftc; no Xcode project).
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="${APP_NAME:-TouchBarLyrics}"
BUNDLE_ID="${BUNDLE_ID:-com.user.TouchBarLyrics}"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build}"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"

VERSION="${VERSION:-$(<"$ROOT/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(<"$ROOT/BUILD_NUMBER" 2>/dev/null || echo 1)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"   # '-' = ad-hoc; use Developer ID Application for release
INSTALL_APP="${INSTALL_APP:-$HOME/Applications/$APP_NAME.app}"
SWIFTC="${SWIFTC:-xcrun swiftc}"

print() { printf '%s\n' "$*"; }

print "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
print "    identity: ${CODESIGN_IDENTITY}"
print "    output:   $APP_PATH"

mkdir -p "$BUILD_DIR"
rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR"

# Plist source kept in repo; versions are injected below.
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

# Compile all app sources; no package manager / generated files.
${=SWIFTC} \
  -O \
  -swift-version 5 \
  -framework Cocoa \
  -framework CoreAudio \
  -framework Accelerate \
  -framework ImageIO \
  -o "$MACOS_DIR/$APP_NAME" \
  "$ROOT"/*.swift

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleExecutable $APP_NAME" \
  -c "Set :CFBundleIdentifier $BUNDLE_ID" \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$CONTENTS/Info.plist"

plutil -lint "$CONTENTS/Info.plist"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  codesign --force --deep --sign "$CODESIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP_PATH"
fi

codesign --verify --deep --strict "$APP_PATH"
print "==> Built and verified: $APP_PATH"

# Optional: ./build.sh --install
if [[ "${1:-}" == "--install" ]]; then
  print "==> Installing to $INSTALL_APP"
  mkdir -p "$(dirname "$INSTALL_APP")"
  rm -rf "$INSTALL_APP"
  cp -R "$APP_PATH" "$INSTALL_APP"

  # Re-sign after copying; ad-hoc identity unless explicitly overridden.
  if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$INSTALL_APP"
  else
    codesign --force --deep --sign "$CODESIGN_IDENTITY" \
      --options runtime \
      --timestamp \
      "$INSTALL_APP"
  fi
  codesign --verify --deep --strict "$INSTALL_APP"
  print "==> Installed: $INSTALL_APP"
  print "    restart: launchctl kickstart -k gui/\$(id -u)/com.user.touchbarlyrics"
fi
