#!/bin/bash
set -e

echo "Generating macOS AppIcon.icns..."

SRC_IMAGE="/Users/harveyopenclaw/Desktop/Podcast tracker Expo/assets/icon.png"
ICONSET_DIR="/Users/harveyopenclaw/Desktop/Podcast tracker MacOS/Sources/PodcastTracker/Resources/AppIcon.iconset"
OUT_ICNS="/Users/harveyopenclaw/Desktop/Podcast tracker MacOS/Sources/PodcastTracker/Resources/AppIcon.icns"

mkdir -p "$ICONSET_DIR"

# Resize images using sips
sips -z 16 16     "$SRC_IMAGE" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$SRC_IMAGE" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$SRC_IMAGE" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$SRC_IMAGE" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$SRC_IMAGE" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$SRC_IMAGE" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$SRC_IMAGE" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$SRC_IMAGE" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$SRC_IMAGE" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$SRC_IMAGE" --out "$ICONSET_DIR/icon_512x512@2x.png"

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"

# Clean up
rm -rf "$ICONSET_DIR"

echo "Successfully generated AppIcon.icns at $OUT_ICNS!"
