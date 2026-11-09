#!/bin/bash
set -euo pipefail
# Package copies of the signed archives; never compile or modify the originals.
source "$(dirname "$0")/build-config.sh"
: "${APP_VERSION:?Set APP_VERSION to X.Y.Z}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER to a positive integer}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || exit 2
platform="${1:-}"
case "$platform" in
  ios|macos) ;;
  *) echo 'Usage: scripts/preview-release.sh ios|macos (after archiving that platform)' >&2; exit 2 ;;
esac
archive="${SLIPSTREAM_ARCHIVE_PATH:-$SLIPSTREAM_ROOT/build-release/Slipstream-$platform.xcarchive}"
app="$(python3 - "$archive" <<'PY'
import os, plistlib, sys
from pathlib import Path
archive = Path(sys.argv[1])
metadata = plistlib.loads((archive / 'Info.plist').read_bytes())['ApplicationProperties']
if (metadata['CFBundleShortVersionString'], str(metadata['CFBundleVersion'])) != (os.environ['APP_VERSION'], os.environ['BUILD_NUMBER']):
    sys.exit('Archive version/build does not match the requested preview.')
print(archive / 'Products' / metadata['ApplicationPath'])
PY
)"
[[ -d "$app" ]] || { echo 'Archived app not found.' >&2; exit 1; }
tag="v$APP_VERSION-preview.$BUILD_NUMBER"
output="$SLIPSTREAM_ROOT/build-preview/$tag"
if [[ "$platform" == macos ]]; then
  [[ ! -e "$output/macos" ]] || { echo 'Mac preview copy already exists.' >&2; exit 1; }
  mkdir -p "$output/macos"
  ditto "$app" "$output/macos/Slipstream.app"
  # App Store profiles do not belong in a Developer ID download.
  rm -f "$output/macos/Slipstream.app/Contents/embedded.provisionprofile"
else
  [[ ! -e "$output/Payload" ]] || { echo 'IPA preview copy already exists.' >&2; exit 1; }
  mkdir -p "$output/Payload"
  ditto "$app" "$output/Payload/Slipstream.app"
  while IFS= read -r -d '' binary; do
    if codesign -d "$binary" >/dev/null 2>&1; then codesign --remove-signature "$binary"; fi
  done < <(find "$output/Payload" -type f -print0)
  find "$output/Payload" -name _CodeSignature -type d -prune -exec rm -r {} +
  find "$output/Payload" -name embedded.mobileprovision -type f -delete
  (cd "$output" && ditto -c -k --keepParent Payload "Slipstream-$tag-altstore.ipa")
fi
echo "Preview copy: $output"
