#!/bin/zsh
# One-time setup for the maintainer: creates the project's self-signed code-signing certificate,
# imports it into the login keychain (for local builds) and uploads it to the GitHub repo secrets
# so the release workflow signs every release with it.
#
# Why: macOS lists widgets only for apps with a certificate-based signature (ad-hoc is ignored).
# A self-signed certificate is enough and users don't need to trust it, so releases signed this
# way get working widgets with no setup on the user's side. Keep the certificate stable: the
# signature's identity is also what macOS ties Calendar/Location permissions to.
#
# Usage: scripts/setup-release-signing.sh   (needs `gh auth login` once)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="MyZman Release Signing"
DIR=certs
P12="$DIR/MyZmanRelease.p12"
PWFILE="$DIR/MyZmanRelease.p12.password.txt"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "• '$NAME' כבר קיימת ב-Keychain."
else
  mkdir -p "$DIR"
  printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=%s\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$NAME" > "$DIR/cs.cnf"
  openssl req -x509 -newkey rsa:2048 -keyout "$DIR/key.pem" -out "$DIR/MyZmanRelease.cert.pem" \
    -days 7300 -nodes -config "$DIR/cs.cnf" 2>/dev/null
  PW=$(openssl rand -base64 18)
  print -r -- "$PW" > "$PWFILE"
  # -legacy: Keychain only reads the old PKCS#12 encryption (LibreSSL uses it by default).
  LEGACY=(); openssl version | grep -q "^OpenSSL 3" && LEGACY=(-legacy)
  openssl pkcs12 -export "${LEGACY[@]}" -inkey "$DIR/key.pem" -in "$DIR/MyZmanRelease.cert.pem" \
    -out "$P12" -passout pass:"$PW" -name "$NAME"
  rm -f "$DIR/key.pem" "$DIR/cs.cnf"
  chmod 600 "$P12" "$PWFILE"
  security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PW" -T /usr/bin/codesign -A
  echo "✓ נוצרה התעודה '$NAME' ויובאה ל-Keychain."
fi

if [[ -f "$P12" && -f "$PWFILE" ]]; then
  gh secret set SIGNING_CERT_P12_BASE64 --body "$(base64 -i "$P12")"
  gh secret set SIGNING_CERT_P12_PASSWORD --body "$(cat "$PWFILE")"
  echo "✓ הסודות הועלו ל-GitHub. כל גרסה מעכשיו תיחתם בתעודה הזו."
else
  echo "! לא נמצא $P12 – הסודות לא הועלו (התעודה נוצרה במחשב אחר?)."
fi

echo
echo "שמרו גיבוי של התיקייה $DIR/ (הקובץ ‎.p12 והסיסמה) במקום בטוח. היא לא נשמרת ב-git."
echo "אם היא תאבד, אפשר ליצור תעודה חדשה – אבל משתמשים קיימים יתבקשו לאשר שוב גישה ליומן."
