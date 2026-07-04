#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacGauge"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
OUTPUT_DMG="${OUTPUT_DMG:-}"
NOTARY_PROFILE="${MACGAUGE_NOTARY_PROFILE:-${NOTARY_PROFILE:-notarytool-dmg}}"

usage() {
  echo "Usage: $0 [--output <path>]"
  echo
  echo "Environment:"
  echo "  MACGAUGE_SIGN_IDENTITY   Developer ID Application identity. Defaults to the first local one."
  echo "  MACGAUGE_NOTARY_PROFILE  notarytool keychain profile. Defaults to notarytool-dmg."
  echo "  OUTPUT_DMG             Output DMG path. Defaults to dist/MacGauge-v<version>.dmg."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --output" >&2; exit 64; }
      OUTPUT_DMG="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install it with: brew install create-dmg" >&2
  exit 69
fi

SIGN_IDENTITY="${MACGAUGE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "No Developer ID Application signing identity found." >&2
  exit 65
fi

echo "==> Validating notary profile: $NOTARY_PROFILE"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null

echo "==> Staging release bundle"
CONFIG=release ./script/build_and_run.sh stage

echo "==> Signing with Developer ID + Hardened Runtime"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE/Contents/MacOS/MacFanHelper"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE/Contents/Resources/macfan"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE"

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(codesign -dvv "$APP_BUNDLE" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$SIGNING_DETAILS" || {
  echo "App is not signed with Developer ID Application." >&2
  exit 65
}
grep -q "^Timestamp=" <<<"$SIGNING_DETAILS" || {
  echo "App signature is missing a secure timestamp." >&2
  exit 65
}
grep -q "^Runtime Version=" <<<"$SIGNING_DETAILS" || {
  echo "App signature is missing Hardened Runtime." >&2
  exit 65
}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ -z "$OUTPUT_DMG" ]]; then
  OUTPUT_DMG="$DIST_DIR/$APP_NAME-v$VERSION.dmg"
fi

echo "==> Creating $OUTPUT_DMG"
rm -f "$OUTPUT_DMG"
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 150 200 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 450 200 \
  --no-internet-enable \
  "$OUTPUT_DMG" \
  "$APP_BUNDLE"

echo "==> Signing DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUTPUT_DMG"
codesign --verify --verbose=2 "$OUTPUT_DMG"
hdiutil verify "$OUTPUT_DMG"

echo "==> Notarizing DMG"
xcrun notarytool submit "$OUTPUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling DMG"
xcrun stapler staple "$OUTPUT_DMG"
xcrun stapler validate "$OUTPUT_DMG"

echo "==> Gatekeeper assessment"
spctl -a -t open --context context:primary-signature -vv "$OUTPUT_DMG"

echo "==> SHA-256"
(cd "$(dirname "$OUTPUT_DMG")" && shasum -a 256 "$(basename "$OUTPUT_DMG")" | tee "$(basename "$OUTPUT_DMG").sha256")
