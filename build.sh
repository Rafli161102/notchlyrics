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

# Parse flags: --install, --universal, --package
DO_INSTALL=0
DO_UNIVERSAL=0
DO_PACKAGE=0
for arg in "$@"; do
  case "$arg" in
    --install) DO_INSTALL=1 ;;
    --universal) DO_UNIVERSAL=1 ;;
    --package) DO_PACKAGE=1 ;;
  esac
done

mkdir -p "$BUILD_DIR"
rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"

# Plist source kept in repo; versions are injected below.
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

FRAMEWORKS=(
  -framework Cocoa
  -framework QuartzCore
  -framework CoreAudio
  -framework Accelerate
  -framework AudioToolbox
  -framework ImageIO
)

# Compile all app sources; universal Mach-O (arm64 + x86_64) when --universal is set.
if [[ "$DO_UNIVERSAL" -eq 1 ]]; then
  print "    arch:     universal (arm64 + x86_64)"
  ${=SWIFTC} -O -swift-version 5 -target arm64-apple-macosx14.2 "${FRAMEWORKS[@]}" -o "$BUILD_DIR/$APP_NAME-arm64" "$ROOT"/*.swift
  ${=SWIFTC} -O -swift-version 5 -target x86_64-apple-macosx14.2 "${FRAMEWORKS[@]}" -o "$BUILD_DIR/$APP_NAME-x86_64" "$ROOT"/*.swift
  lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" -output "$MACOS_DIR/$APP_NAME"
  rm -f "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"
else
  ${=SWIFTC} -O -swift-version 5 "${FRAMEWORKS[@]}" -o "$MACOS_DIR/$APP_NAME" "$ROOT"/*.swift
fi

# Bundle MediaRemoteAdapter automatically when present on the build machine (makes .app portable without Atoll)
BUNDLE_ADAPTER="${BUNDLE_ADAPTER:-1}"
if [[ "$BUNDLE_ADAPTER" -eq 1 ]]; then
  ADAPTER_SRC_DIR=""
  if [[ -x "/Applications/Atoll.app/Contents/Resources/mediaremote-adapter.pl" && -d "/Applications/Atoll.app/Contents/Resources/MediaRemoteAdapter.framework" ]]; then
    ADAPTER_SRC_DIR="/Applications/Atoll.app/Contents/Resources"
  elif [[ -x "$HOME/Library/Application Support/TouchBarLyrics/MediaRemoteAdapter/mediaremote-adapter.pl" ]]; then
    ADAPTER_SRC_DIR="$HOME/Library/Application Support/TouchBarLyrics/MediaRemoteAdapter"
  fi
  if [[ -n "$ADAPTER_SRC_DIR" ]]; then
    cp "$ADAPTER_SRC_DIR/mediaremote-adapter.pl" "$CONTENTS/Resources/mediaremote-adapter.pl"
    chmod +x "$CONTENTS/Resources/mediaremote-adapter.pl"
    cp -R "$ADAPTER_SRC_DIR/MediaRemoteAdapter.framework" "$CONTENTS/Resources/MediaRemoteAdapter.framework"
    print "    bundled:  MediaRemoteAdapter from $ADAPTER_SRC_DIR"
  fi
fi

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
if [[ "$DO_INSTALL" -eq 1 ]]; then
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

# Optional: ./build.sh --package (distributable macOS zip archive)
if [[ "$DO_PACKAGE" -eq 1 ]]; then
  ZIP_OUT="$BUILD_DIR/$APP_NAME-$VERSION-macOS.zip"
  rm -f "$ZIP_OUT"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_OUT"
  print "==> Packaged archive: $ZIP_OUT"
fi
