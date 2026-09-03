#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PodTrackio"
APP_EXECUTABLE_NAME="PodTrackio"
BUNDLE_ID="com.tangenix.podtrackio"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_DIR="$ROOT_DIR/.swift-build"
DERIVED_DATA_DIR="$SCRATCH_DIR/xcode-derived-data"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
DMG_PATH="$ROOT_DIR/$APP_NAME.dmg"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$SCRATCH_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRATCH_DIR/swiftpm-module-cache"

build_app() {
  mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$DIST_DIR"
  xcodebuild \
    -project "$ROOT_DIR/PodTrackio.xcodeproj" \
    -scheme PodTrackio \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -allowProvisioningUpdates \
    build >/dev/null

  rm -rf "$APP_BUNDLE"
  ditto "$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app" "$APP_BUNDLE"
}

create_dmg() {
  local staging_dir
  staging_dir="$(mktemp -d "$DIST_DIR/.${APP_NAME}-dmg.XXXXXX")"
  trap 'rm -rf "$staging_dir"' RETURN

  ditto "$APP_BUNDLE" "$staging_dir/$APP_NAME.app"
  ln -s /Applications "$staging_dir/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$staging_dir" -format UDZO -ov "$DMG_PATH" >/dev/null
  echo "Created $DMG_PATH"
}

stop_app() {
  pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    plutil -lint "$APP_CONTENTS/Info.plist"
    codesign --verify --deep --strict "$APP_BUNDLE"
    codesign -d --entitlements - "$APP_BUNDLE" 2>&1 | grep -q "com.apple.developer.applesignin"
    open_app
    sleep 2
    pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    echo "$APP_BUNDLE launched successfully"
    ;;
  --dmg|dmg)
    create_dmg
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--dmg]" >&2
    exit 2
    ;;
esac
