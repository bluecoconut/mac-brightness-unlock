#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
APP_NAME="Full Mac"
APP="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE="$APP/Contents/MacOS/FullMac"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
ARCHS_VALUE="${ARCHS:-arm64 x86_64}"

if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: Xcode command-line tools are required" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/AppIcon.iconset"

ARCH_FLAGS=()
for arch in $ARCHS_VALUE; do
    ARCH_FLAGS+=("-arch" "$arch")
done

xcrun clang \
    -fobjc-arc \
    -fmodules \
    -Wall \
    -Wextra \
    "${ARCH_FLAGS[@]}" \
    -mmacosx-version-min="$DEPLOYMENT_TARGET" \
    -framework AppKit \
    -framework CoreGraphics \
    -framework ServiceManagement \
    "$ROOT/Sources/AppDelegate.m" \
    -o "$EXECUTABLE"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

for spec in \
    "16:icon_16x16.png" \
    "32:icon_16x16@2x.png" \
    "32:icon_32x32.png" \
    "64:icon_32x32@2x.png" \
    "128:icon_128x128.png" \
    "256:icon_128x128@2x.png" \
    "256:icon_256x256.png" \
    "512:icon_256x256@2x.png" \
    "512:icon_512x512.png"; do
    size="${spec%%:*}"
    name="${spec#*:}"
    sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" \
        --out "$BUILD_DIR/AppIcon.iconset/$name" >/dev/null
done
cp "$ROOT/Resources/AppIcon.png" "$BUILD_DIR/AppIcon.iconset/icon_512x512@2x.png"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$BUILD_DIR/AppIcon.iconset"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
