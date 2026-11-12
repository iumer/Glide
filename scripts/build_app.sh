#!/bin/zsh
# Builds Glide.app (universal, release), signs it, and optionally installs to ~/Applications.
# Usage: scripts/build_app.sh [--install]
set -euo pipefail
cd "${0:A:h}/.."

VERSION="1.0.0"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
APP="build/Glide.app"
IDENTITY="${GLIDE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"

echo "▸ Running self-tests"
swift build --product GlideSelfTest >/dev/null
.build/debug/GlideSelfTest | tail -1

echo "▸ Building release (arm64 + x86_64)"
swift build -c release --product Glide --arch arm64 --arch x86_64 >/dev/null
BIN="$(swift build -c release --product Glide --arch arm64 --arch x86_64 --show-bin-path)/Glide"

echo "▸ Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glide"

if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Glide</string>
  <key>CFBundleDisplayName</key><string>Glide</string>
  <key>CFBundleIdentifier</key><string>com.itech.Glide</string>
  <key>CFBundleExecutable</key><string>Glide</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 iTech</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ Signing with: ${IDENTITY:-ad-hoc}"
codesign --force --options runtime --timestamp=none --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict "$APP" && echo "  signature OK"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/Glide.app"
  mkdir -p "$HOME/Applications"
  pkill -x Glide 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "▸ Installed to $DEST"
fi
echo "✓ Done: $APP"
