#!/bin/bash
set -euo pipefail
# Build disposable release copies without touching signed archives or credentials.
source "$(dirname "$0")/build-config.sh"
: "${APP_VERSION:?Set APP_VERSION to X.Y.Z}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER to a positive integer}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || exit 2
tag="v$APP_VERSION-preview.$BUILD_NUMBER"
output="$SLIPSTREAM_ROOT/build-preview/$tag"
[[ ! -e "$output" ]] || { echo 'Preview output already exists; use a new build number.' >&2; exit 1; }
mkdir -p "$output/Payload"
export SLIPSTREAM_CONFIGURATION=Release
SLIPSTREAM_DERIVED_DATA_PATH="$output/ios" ./scripts/build.sh ios-device CODE_SIGNING_ALLOWED=NO
ditto "$output/ios/Build/Products/Release-iphoneos/Slipstream-iOS.app" "$output/Payload/Slipstream.app"
# Dependencies may contain vendor signatures even in an unsigned app build.
while IFS= read -r -d '' binary; do
  if codesign -d "$binary" >/dev/null 2>&1; then codesign --remove-signature "$binary"; fi
done < <(find "$output/Payload" -type f -print0)
find "$output/Payload" -name _CodeSignature -type d -prune -exec rm -r {} +
find "$output/Payload" -name embedded.mobileprovision -type f -delete
(cd "$output" && ditto -c -k --keepParent Payload "Slipstream-$tag-altstore.ipa")
SLIPSTREAM_DERIVED_DATA_PATH="$output/macos" ./scripts/build.sh macos --ad-hoc \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
ditto -c -k --sequesterRsrc --keepParent "$output/macos/Build/Products/Release/Slipstream.app" \
  "$output/Slipstream-$tag-macOS.zip"
echo "Preview packages: $output"
