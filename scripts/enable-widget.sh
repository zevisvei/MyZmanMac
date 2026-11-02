#!/bin/zsh
# Re-signs the installed MyZman.app with your own free "Apple Development" certificate,
# so macOS lists its widgets in the widget gallery (it hides widgets of ad-hoc signed apps).
#
# One-time setup (free):
#   1. Install Xcode from the App Store and open it once.
#   2. Xcode ▸ Settings ▸ Accounts ▸ "+" ▸ sign in with your Apple ID.
#   3. Select the account ▸ "Manage Certificates…" ▸ "+" ▸ "Apple Development".
# Then run:  zsh enable-widget.sh   (or: scripts/enable-widget.sh)
set -euo pipefail

APP="${1:-/Applications/MyZman.app}"
WEX="$APP/Contents/PlugIns/MyZmanWidget.appex"
[[ -d "$WEX" ]] || { echo "✗ לא נמצא $APP – התקינו את MyZman קודם."; exit 1; }

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)}"
if [[ -z "$IDENTITY" ]]; then
  cat <<'MSG'
✗ לא נמצאה תעודת "Apple Development" במחשב.

כדי ליצור אחת בחינם:
  1. התקינו את Xcode מה-App Store ופתחו אותו פעם אחת.
  2. Xcode ← Settings ← Accounts ← "+" ← התחברו עם ה-Apple ID שלכם.
  3. בחרו בחשבון ← "Manage Certificates…" ← "+" ← "Apple Development".
ואז הריצו את הסקריפט הזה שוב.
MSG
  exit 1
fi

echo "› חותם עם: $IDENTITY"
ENT=$(mktemp -t widget).entitlements
cat > "$ENT" <<ENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
  <array><string>/Library/Application Support/MyZman/</string></array>
</dict>
</plist>
ENTS

pkill -x MyZman 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENT" "$WEX"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# Make the system pick up the newly signed widget.
pluginkit -a "$WEX" 2>/dev/null || true
pluginkit -e use -i com.myzman.mac.widget 2>/dev/null || true
killall chronod 2>/dev/null || true
open "$APP"

echo "✓ מוכן. לחיצה ימנית על שולחן העבודה ← „עריכת ווידג'טים” ← חפשו „זמנים”."
echo "  (ייתכן שתתבקשו לאשר שוב גישה ליומן ולמיקום, כי החתימה השתנתה.)"
