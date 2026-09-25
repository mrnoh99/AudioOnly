#!/usr/bin/env bash
# AudioOnly.app 번들을 만든다.
#   ./scripts/build-app.sh            # 현재 Mac 아키텍처용
#   UNIVERSAL=1 ./scripts/build-app.sh  # Apple Silicon + Intel 유니버설
#   DMG=1 ./scripts/build-app.sh        # build/AudioOnly.dmg 도 생성
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="AudioOnly"
BUNDLE_ID="com.audioonly.app"
VERSION="${VERSION:-1.1.0}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> swift build (release)"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> $APP 생성"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

echo "==> 앱 아이콘(.icns)"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp Sources/AudioOnly/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc 코드 서명"
codesign --force --deep --sign - "$APP"

if [[ "${DMG:-0}" == "1" ]]; then
  echo "==> DMG 생성"
  rm -f "$BUILD_DIR/$APP_NAME.dmg"
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$BUILD_DIR/$APP_NAME.dmg"
fi

echo "완료: $APP"
