#!/bin/zsh
# Makes MyZman's widgets appear in the widget gallery for an app that was signed ad-hoc
# (e.g. built from source without a certificate). Official releases are already signed and
# don't need this.
#
# macOS lists widgets only for apps with a certificate-based signature. Any certificate works,
# even a self-signed, untrusted one – so this creates a local one if needed (no Xcode, no Apple ID)
# and re-signs the installed app with it.
#
# Usage: zsh enable-widget.sh [path/to/MyZman.app] [--prepare]
#   --prepare: only the checks and the certificate (exit status says whether re-signing can go ahead);
#              the app runs this first, so a failure shows in its window instead of leaving it waiting.
set -euo pipefail
PREPARE=0; [[ "${2:-}" == "--prepare" ]] && PREPARE=1

APP="${1:-/Applications/MyZman.app}"
WEX="$APP/Contents/PlugIns/MyZmanWidget.appex"
[[ -d "$WEX" ]] || { echo "✗ לא נמצא $APP – התקינו את MyZman קודם."; exit 1; }
[[ -w "$APP" && -w "$APP/Contents" ]] || { echo "✗ אין הרשאת כתיבה ל-$APP (העבירו את האפליקציה לתיקיית היישומים שלכם)."; exit 1; }

pick_identity() {
  local ids m
  ids=$(security find-identity -p codesigning 2>/dev/null)
  for n in "MyZman Release Signing" "Apple Development: " "MyZman Local Signing"; do
    m=$(print -r -- "$ids" | grep -m1 -o "\"${n}[^\"]*\"" | tr -d '"' || true)
    [[ -n "$m" ]] && { print -r -- "$m"; return; }
  done
}

IDENTITY="${SIGN_IDENTITY:-$(pick_identity)}"
if [[ -z "$IDENTITY" ]]; then
  echo "› יוצר תעודת חתימה מקומית (פעם אחת)…"
  TMP=$(mktemp -d)
  printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=MyZman Local Signing\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > "$TMP/cs.cnf"
  openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 7300 -nodes -config "$TMP/cs.cnf" 2>/dev/null
  PW=$(openssl rand -hex 12)
  LEGACY=(); openssl version | grep -q "^OpenSSL 3" && LEGACY=(-legacy)
  openssl pkcs12 -export "${LEGACY[@]}" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" \
    -passout pass:"$PW" -name "MyZman Local Signing"
  # -A (any app may use the key) avoids a Keychain prompt in the one-click flow. Acceptable for this
  # throwaway local key, which only ever signs this Mac's own copy; the release key never gets it.
  security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PW" -T /usr/bin/codesign -A >/dev/null
  rm -rf "$TMP"
  IDENTITY="MyZman Local Signing"
fi

echo "› חותם עם: $IDENTITY"
(( PREPARE )) && exit 0
ENT=$(mktemp -d)
cat > "$ENT/widget.plist" <<ENTS
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
cat > "$ENT/app.plist" <<ENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.personal-information.calendars</key><true/>
  <key>com.apple.security.personal-information.location</key><true/>
</dict>
</plist>
ENTS

pkill -x MyZman 2>/dev/null || true
# Re-sign only once it has quit (up to 5 s).
for _ in {1..50}; do pgrep -x MyZman >/dev/null || break; sleep 0.1; done
# Whatever happens from here on, don't leave the app closed.
trap 'open "$APP"' EXIT
xattr -d com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENT/widget.plist" "$WEX"
codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENT/app.plist" "$APP"
rm -rf "$ENT"

# Make the system pick up the newly signed widget.
pluginkit -a "$WEX" 2>/dev/null || true
pluginkit -e use -i com.myzman.mac.widget 2>/dev/null || true
killall chronod 2>/dev/null || true

echo "✓ מוכן. לחיצה ימנית על שולחן העבודה ← „עריכת ווידג'טים” ← חפשו „זמנים”."
echo "  (ייתכן שתתבקשו לאשר שוב גישה ליומן ולמיקום, כי החתימה השתנתה.)"
