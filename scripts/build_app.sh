#!/bin/zsh
# Builds MyZman.app (release, universal when possible) into ./build and optionally installs it.
# Usage: scripts/build_app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/MyZman.app
VERSION="${VERSION:-1.0.0}"

echo "› Compiling…"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  OUT=.build/apple/Products/Release
else
  swift build -c release
  OUT=.build/release
fi

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/he.lproj"
# Declares Hebrew as the app's language, so system controls (date picker, menus, alerts) use Hebrew.
echo '"CFBundleDisplayName" = "זמנים";' > "$APP/Contents/Resources/he.lproj/InfoPlist.strings"
cp "$OUT/MyZmanMac" "$APP/Contents/MacOS/MyZman"

# Widget extension
WEX="$APP/Contents/PlugIns/MyZmanWidget.appex"
mkdir -p "$WEX/Contents/MacOS"
cp "$OUT/MyZmanWidget" "$WEX/Contents/MacOS/MyZmanWidget"
cat > "$WEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MyZmanWidget</string>
  <key>CFBundleDisplayName</key><string>זמנים</string>
  <key>CFBundleIdentifier</key><string>com.myzman.mac.widget</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleDevelopmentRegion</key><string>he</string>
  <key>DTPlatformName</key><string>macosx</string>
  <key>CFBundleExecutable</key><string>MyZmanWidget</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST
cat > build/widget.entitlements <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
  <array><string>/Library/Application Support/MyZman/</string></array>
</dict>
</plist>
ENT

if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp scripts/enable-widget.sh "$APP/Contents/Resources/enable-widget.sh"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MyZman</string>
  <key>CFBundleDisplayName</key><string>זמנים</string>
  <key>CFBundleIdentifier</key><string>com.myzman.mac</string>
  <key>CFBundleExecutable</key><string>MyZman</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>he</string>
  <key>CFBundleLocalizations</key><array><string>he</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.lifestyle</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>המיקום משמש לחישוב הזמנים לפי המקום שבו אתם נמצאים.</string>
  <key>NSLocationUsageDescription</key><string>המיקום משמש לחישוב הזמנים לפי המקום שבו אתם נמצאים.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>כדי להוסיף את הזמנים והתאריך העברי ללוח נפרד ביומן.</string>
  <key>NSCalendarsUsageDescription</key><string>כדי להוסיף את הזמנים והתאריך העברי ללוח נפרד ביומן.</string>
  <key>NSHumanReadableCopyright</key><string>LGPL 2.1 · Based on MyZman and KosherJava</string>
</dict>
</plist>
PLIST

# Signing identity: $SIGN_IDENTITY, else the project's release certificate, an Apple Development
# certificate or a local self-signed one (see enable-widget.sh), else ad-hoc. Any certificate works
# (even an untrusted self-signed one); macOS just won't list widgets of ad-hoc signed apps.
pick_identity() {
  local ids m
  ids=$(security find-identity -p codesigning 2>/dev/null)
  for n in "MyZman Release Signing" "Apple Development: " "MyZman Local Signing"; do
    m=$(print -r -- "$ids" | grep -m1 -o "\"${n}[^\"]*\"" | tr -d '"' || true)
    [[ -n "$m" ]] && { print -r -- "$m"; return; }
  done
  print -- "-"
}
IDENTITY="${SIGN_IDENTITY:-$(pick_identity)}"
# Hardened runtime needs explicit entitlements for Calendar and Location access.
cat > build/app.entitlements <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.personal-information.calendars</key><true/>
  <key>com.apple.security.personal-information.location</key><true/>
</dict>
</plist>
ENT
echo "› Signing (${IDENTITY})"
# A secure timestamp is required for notarization (and unavailable for ad-hoc signing).
TS=(); [[ "$IDENTITY" != "-" ]] && TS=(--timestamp)
codesign --force --options runtime "${TS[@]}" --sign "$IDENTITY" --entitlements build/widget.entitlements "$WEX"
codesign --force --options runtime "${TS[@]}" --sign "$IDENTITY" --entitlements build/app.entitlements "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MyZman 2>/dev/null || true
  rm -rf /Applications/MyZman.app
  cp -R "$APP" /Applications/
  open /Applications/MyZman.app
  echo "✓ Installed to /Applications/MyZman.app"
else
  echo "✓ Built $APP  (run: open $APP)"
fi
