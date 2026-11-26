#!/usr/bin/env zsh
set -euo pipefail

# Notarize an already Developer-ID-signed app. Requires Apple notarytool credentials.
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="${APP_NAME:-TouchBarLyrics}"
APP_PATH="${APP_PATH:-$ROOT/.build/$APP_NAME.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-TouchBarLyricsNotary}"
ZIP_PATH="${ZIP_PATH:-$ROOT/.build/$APP_NAME-notary.zip}"

print() { printf '%s\n' "$*"; }

if [[ ! -d "$APP_PATH" ]]; then
  print "error: app not found: $APP_PATH"
  print "build first: CODESIGN_IDENTITY='Developer ID Application: ... (TEAMID)' ./build.sh"
  exit 1
fi

# Refuse ad-hoc / no-identity; Apple notarization requires Developer ID Application.
SIGINFO="$(codesign -dv "$APP_PATH" 2>&1 || true)"
if print -r -- "$SIGINFO" | grep -q "Signature=adhoc"; then
  print "error: app is ad-hoc signed; notarization requires Developer ID Application"
  print "$SIGINFO"
  exit 1
fi
if print -r -- "$SIGINFO" | grep -q "Signature=unsigned"; then
  print "error: app is unsigned; notarization requires Developer ID Application"
  exit 1
fi

print "==> Verifying signature"
codesign --verify --deep --strict "$APP_PATH"

print "==> Creating $ZIP_PATH"
mkdir -p "$(dirname "$ZIP_PATH")"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

print "==> Submitting to Apple notarytool (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

print "==> Stapling"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

print "==> Final verification"
codesign --verify --deep --strict "$APP_PATH"
print "==> Notarized + stapled: $APP_PATH"
