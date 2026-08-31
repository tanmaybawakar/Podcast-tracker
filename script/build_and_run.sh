#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PodTrackio"
EXECUTABLE_NAME="PodcastTracker"
BUNDLE_ID="com.tangenix.podtrackio"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_DIR="$ROOT_DIR/.swift-build"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$SCRATCH_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRATCH_DIR/swiftpm-module-cache"

build_app() {
  mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
  swift build --disable-sandbox -Xswiftc -disable-sandbox --scratch-path "$SCRATCH_DIR"
  local build_dir
  build_dir="$(swift build --show-bin-path --scratch-path "$SCRATCH_DIR")"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_dir/$EXECUTABLE_NAME" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT_DIR/Info.plist" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE_NAME" "$APP_CONTENTS/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$APP_CONTENTS/Info.plist" 2>/dev/null || true
  ditto "$build_dir/PodcastTracker_PodcastTracker.bundle" "$APP_RESOURCES/PodcastTracker_PodcastTracker.bundle"
  ditto "$build_dir/YouTubeKit_YouTubeKit.bundle" "$APP_RESOURCES/YouTubeKit_YouTubeKit.bundle"
  cp "$ROOT_DIR/Sources/PodcastTracker/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
}

stop_app() {
  pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
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
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    plutil -lint "$APP_CONTENTS/Info.plist"
    codesign --verify --deep --strict "$APP_BUNDLE"
    open_app
    sleep 2
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    echo "$APP_BUNDLE launched successfully"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
