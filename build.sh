#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "Building DynamicDesktop..."

APP_NAME="DynamicDesktop"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"

case "$BUILD_ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $BUILD_ARCH (expected arm64 or x86_64)" >&2; exit 1 ;;
esac

mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Compile Swift sources
swiftc -O -target "$BUILD_ARCH-apple-macosx14.0" \
  Sources/WallpaperDetector.swift \
  Sources/WallpaperDownloader.swift \
  Sources/AmbientSoundManager.swift \
  Sources/DesktopWallpaperWindow.swift \
  Sources/WallpaperEngine.swift \
  Sources/FloatingButtonPanel.swift \
  Sources/StatusBarMenuController.swift \
  Sources/main.swift \
  -o "$MACOS/$APP_NAME"

# Create Info.plist
cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.liuming.dynamicdesktop</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -f "AppIcon.icns" ]; then
  cp "AppIcon.icns" "$RESOURCES/"
fi

echo "Build successful: $APP_BUNDLE"
