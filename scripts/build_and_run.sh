#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
# Brand name: the .app bundle, executable, and display name the user sees.
APP_NAME="MacGauge"
# SwiftPM package name. Internal identifiers (package, products, bundle ID,
# helper label) deliberately keep the MacFan prefix so installed helpers,
# authorizations, and user defaults survive the brand rename.
PACKAGE_NAME="MacFan"
# The app's SwiftPM product; distinct from "macfan" (CLI) because the two
# would collide case-insensitively in the build directory.
APP_PRODUCT="MacFanApp"
CLI_NAME="macfan"
HELPER_NAME="MacFanHelper"
BUNDLE_ID="com.stevenacz.MacFan"
MIN_SYSTEM_VERSION="13.0"
# Overridable for local update-flow testing (fake higher version builds).
APP_VERSION="${APP_VERSION:-1.5.0}"
APP_BUILD="${APP_BUILD:-11}"
# Sparkle in-app updates: public feed + EdDSA public key (private key lives in
# the login Keychain; never in the repo).
SPARKLE_FEED_URL="https://github.com/StevenACZ/MacGauge/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_ED_KEY="EjJwYzuWlNuccLSqIcVxHRlGMLg7R6ONwpUjnVbFqY8="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_LAUNCH_DAEMONS="$APP_CONTENTS/Library/LaunchDaemons"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
HELPER_PLIST_SRC="$ROOT_DIR/Resources/LaunchDaemons/com.stevenacz.MacFan.XPCHelper.plist"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

usage() {
  echo "usage: $0 [stage|run|--verify|--install|--install-only|--debug|--logs|--telemetry|--dmg]" >&2
}

kill_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  # Legacy process name from before the MacGauge brand rename.
  pkill -x "MacFan" >/dev/null 2>&1 || true
}

stage_bundle() {
  swift build -c "$CONFIG" --product "$APP_PRODUCT"
  swift build -c "$CONFIG" --product "$CLI_NAME"
  swift build -c "$CONFIG" --product "$HELPER_NAME"

  local build_dir
  build_dir="$(swift build -c "$CONFIG" --show-bin-path)"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_LAUNCH_DAEMONS"

  cp "$build_dir/$APP_PRODUCT" "$APP_BINARY"
  cp "$build_dir/$CLI_NAME" "$APP_RESOURCES/$CLI_NAME"
  cp "$build_dir/$HELPER_NAME" "$APP_MACOS/$HELPER_NAME"
  cp "$HELPER_PLIST_SRC" "$APP_LAUNCH_DAEMONS/"
  chmod +x "$APP_BINARY" "$APP_RESOURCES/$CLI_NAME" "$APP_MACOS/$HELPER_NAME"

  # SwiftPM target resources (localized strings). Bundle.module aborts at
  # launch if this bundle is missing from Contents/Resources.
  local resources_bundle="$build_dir/${PACKAGE_NAME}_${APP_PRODUCT}.bundle"
  if [ ! -d "$resources_bundle" ]; then
    echo "error: missing SwiftPM resources bundle at $resources_bundle" >&2
    exit 1
  fi
  cp -R "$resources_bundle" "$APP_RESOURCES/"

  # Sparkle.framework ships inside the bundle; the app binary resolves it via
  # the @executable_path/../Frameworks rpath set in Package.swift.
  local sparkle_fw
  sparkle_fw="$(ls -d "$ROOT_DIR"/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework 2>/dev/null | head -1)"
  if [ -z "$sparkle_fw" ]; then
    echo "error: Sparkle.framework artifact not found under .build/artifacts" >&2
    exit 1
  fi
  mkdir -p "$APP_FRAMEWORKS"
  ditto "$sparkle_fw" "$APP_FRAMEWORKS/Sparkle.framework"

  # SwiftPM links the binary with an absolute rpath to the local Sparkle
  # artifact; drop absolute rpaths so the shipped binary only resolves
  # frameworks relative to the bundle (and leaks no local paths).
  otool -l "$APP_BINARY" | grep -A2 'cmd LC_RPATH' | awk '/ path /{print $2}' \
    | while read -r rpath; do
      case "$rpath" in
        /*) install_name_tool -delete_rpath "$rpath" "$APP_BINARY" ;;
      esac
    done

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
</dict>
</plist>
PLIST
}

sign_bundle() {
  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign not found; leaving bundle unsigned" >&2
    return
  fi

  # Sparkle's nested executables keep upstream's signature otherwise; re-sign
  # inside-out so the whole bundle carries one identity.
  local sparkle_fw="$APP_FRAMEWORKS/Sparkle.framework"
  if [ -d "$sparkle_fw" ]; then
    local nested
    for nested in \
      "$sparkle_fw/Versions/B/XPCServices/Downloader.xpc" \
      "$sparkle_fw/Versions/B/XPCServices/Installer.xpc" \
      "$sparkle_fw/Versions/B/Updater.app" \
      "$sparkle_fw/Versions/B/Autoupdate"; do
      codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=entitlements "$nested"
    done
    codesign --force --sign "$SIGN_IDENTITY" "$sparkle_fw"
  fi

  codesign --force --sign "$SIGN_IDENTITY" "$APP_MACOS/$HELPER_NAME"
  codesign --force --sign "$SIGN_IDENTITY" "$APP_RESOURCES/$CLI_NAME"
  codesign --force --sign "$SIGN_IDENTITY" "$APP_BINARY"
  codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

build_dmg() {
  local dmg_path="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
  local staging="$DIST_DIR/dmg-staging"
  rm -rf "$staging" "$dmg_path"
  mkdir -p "$staging"
  cp -R "$APP_BUNDLE" "$staging/"
  ln -s /Applications "$staging/Applications"
  hdiutil create \
    -volname "$APP_NAME $APP_VERSION" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 \
    -srcfolder "$staging" \
    "$dmg_path" >/dev/null
  rm -rf "$staging"
  echo "$dmg_path"
}

case "$MODE" in
  --dmg|dmg) CONFIG="release" ;;
  *) CONFIG="${CONFIG:-debug}" ;;
esac

stage_bundle
sign_bundle

case "$MODE" in
  stage)
    echo "$APP_NAME staged at $APP_BUNDLE"
    ;;
  run)
    kill_existing
    open_app
    ;;
  --verify|verify)
    kill_existing
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME launched from $APP_BUNDLE"
    ;;
  --install|install)
    kill_existing
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED_APP"
    cp -R "$APP_BUNDLE" "$INSTALLED_APP"
    /usr/bin/open -n "$INSTALLED_APP"
    echo "$APP_NAME installed to $INSTALLED_APP"
    ;;
  --install-only|install-only)
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED_APP"
    cp -R "$APP_BUNDLE" "$INSTALLED_APP"
    echo "$APP_NAME installed to $INSTALLED_APP"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    kill_existing
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    kill_existing
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --dmg|dmg)
    dmg_path="$(build_dmg)"
    echo "$APP_NAME $APP_VERSION DMG at $dmg_path"
    ;;
  *)
    usage
    exit 2
    ;;
esac
