#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-config.sh"
: "${APP_VERSION:?Set APP_VERSION}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APP_STORE_CONNECT_KEY_PATH:?Set App Store Connect authentication}"
: "${APP_STORE_CONNECT_KEY_ID:?Set App Store Connect authentication}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Set App Store Connect authentication}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || exit 2
tag="v$APP_VERSION-preview.$BUILD_NUMBER"
output="$SLIPSTREAM_ROOT/build-preview/$tag"
app="$output/macos/Build/Products/Release/Slipstream.app"
zip="$output/Slipstream-$tag-macOS.zip"
# Pin the identity to this team; never fall back to development or ad-hoc signing.
identity="$(security find-identity -v -p codesigning | python3 -c '
import re, sys
team = sys.argv[1]
identities = re.findall(r"([A-F0-9]{40}) \"Developer ID Application: [^\"]+ \(" + re.escape(team) + r"\)\"", sys.stdin.read())
if len(identities) != 1:
    sys.exit("Expected exactly one Developer ID Application identity for the configured team.")
print(identities[0])
' "$APPLE_TEAM_ID")"
# Sign nested code inside out. Resource bundles have no executable to sign.
while IFS= read -r -d '' code; do
  codesign --force --sign "$identity" --options runtime --timestamp "$code"
done < <(find "$app/Contents" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.xpc' -o -name '*.app' \) -print0)
codesign --force --sign "$identity" --options runtime --timestamp \
  --entitlements Config/macOS.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
result="$(mktemp)"
trap 'rm -f "$result"' EXIT
xcrun notarytool submit "$zip" --key "$APP_STORE_CONNECT_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait --timeout 20m --output-format json > "$result"
python3 - "$result" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    sys.exit(f'Notarization was not accepted: {result}')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
# The ticket belongs to the app, so recreate the ZIP after stapling.
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
