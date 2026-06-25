#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="M4FanControl"
CLI_NAME="m4fan"
HELPER_NAME="M4FanHelper"
BUNDLE_ID="com.stevenacz.M4FanControl"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_LAUNCH_DAEMONS="$APP_CONTENTS/Library/LaunchDaemons"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
HELPER_PLIST_SRC="$ROOT_DIR/Resources/LaunchDaemons/com.stevenacz.M4FanControl.XPCHelper.plist"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

usage() {
  echo "usage: $0 [stage|run|--verify|--install|--install-only|--debug|--logs|--telemetry]" >&2
}

kill_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

stage_bundle() {
  swift build --product "$APP_NAME"
  swift build --product "$CLI_NAME"
  swift build --product "$HELPER_NAME"

  local build_dir
  build_dir="$(swift build --show-bin-path)"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_LAUNCH_DAEMONS"

  cp "$build_dir/$APP_NAME" "$APP_BINARY"
  cp "$build_dir/$CLI_NAME" "$APP_RESOURCES/$CLI_NAME"
  cp "$build_dir/$HELPER_NAME" "$APP_MACOS/$HELPER_NAME"
  cp "$HELPER_PLIST_SRC" "$APP_LAUNCH_DAEMONS/"
  chmod +x "$APP_BINARY" "$APP_RESOURCES/$CLI_NAME" "$APP_MACOS/$HELPER_NAME"

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
  <string>M4 Fan Control</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

sign_bundle() {
  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign not found; leaving bundle unsigned" >&2
    return
  fi

  codesign --force --sign "$SIGN_IDENTITY" "$APP_MACOS/$HELPER_NAME"
  codesign --force --sign "$SIGN_IDENTITY" "$APP_RESOURCES/$CLI_NAME"
  codesign --force --sign "$SIGN_IDENTITY" "$APP_BINARY"
  codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

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
  *)
    usage
    exit 2
    ;;
esac
