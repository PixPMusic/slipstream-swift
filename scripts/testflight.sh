#!/bin/bash
set -euo pipefail
# shellcheck source=scripts/build-config.sh
source "$(dirname "$0")/build-config.sh"

action="${1:-archive}"
platform="${2:-ios}"
if [[ $# -ge 2 ]]; then shift 2; elif [[ $# -eq 1 ]]; then shift; fi
case "$platform" in
  ios) scheme=Slipstream-iOS; destination='generic/platform=iOS' ;;
  macos) scheme=Slipstream; destination='generic/platform=macOS' ;;
  *) echo 'Platform must be ios or macos.' >&2; exit 2 ;;
esac
archive_path="${SLIPSTREAM_ARCHIVE_PATH:-$SLIPSTREAM_ROOT/build-release/Slipstream-$platform.xcarchive}"
export_path="${SLIPSTREAM_EXPORT_PATH:-$SLIPSTREAM_ROOT/build-release/export-$platform}"

case "$action" in
  archive)
    settings_file="$(mktemp)"
    trap 'rm "$settings_file"' EXIT
    xcodebuild -project Slipstream.xcodeproj -scheme "$scheme" -configuration Release \
      -destination "$destination" ${build_settings[@]+"${build_settings[@]}"} "$@" \
      -showBuildSettings -json > "$settings_file"
    python3 - "$settings_file" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))[0]['buildSettings']
if settings.get('PRODUCT_BUNDLE_IDENTIFIER', '').startswith('com.example.'):
    sys.exit('Set your bundle ID in Config/Local.xcconfig or SLIPSTREAM_BUNDLE_ID before archiving.')
if not settings.get('DEVELOPMENT_TEAM'):
    sys.exit('Set DEVELOPMENT_TEAM in Config/Local.xcconfig or export APPLE_TEAM_ID before archiving.')
PY
    xcodebuild -project Slipstream.xcodeproj -scheme "$scheme" -configuration Release \
      -destination "$destination" -derivedDataPath "${SLIPSTREAM_DERIVED_DATA_PATH:-build-release/$platform}" \
      -archivePath "$archive_path" -jobs "${BUILD_JOBS:-2}" -allowProvisioningUpdates \
      ${provisioning_auth[@]+"${provisioning_auth[@]}"} \
      ${build_settings[@]+"${build_settings[@]}"} "$@" archive
    ;;
  export|upload)
    [[ -d "$archive_path" ]] || { echo 'Archive not found; run the archive command first.' >&2; exit 1; }
    options="$(mktemp)"
    trap 'rm "$options"' EXIT
    python3 - "$action" "$archive_path" "$options" <<'PY'
import os, plistlib, sys
from pathlib import Path
action, archive, output = sys.argv[1:]
metadata = plistlib.loads((Path(archive) / 'Info.plist').read_bytes())['ApplicationProperties']
options = plistlib.loads(Path('Config/ExportOptions-AppStore.plist').read_bytes())
options['destination'] = 'upload' if action == 'upload' else 'export'
team = os.environ.get('APPLE_TEAM_ID') or metadata.get('Team')
if team:
    options['teamID'] = team
profile = os.environ.get('IOS_PROVISIONING_PROFILE')
if profile:
    options['signingStyle'] = 'manual'
    options['signingCertificate'] = 'Apple Distribution'
    options['provisioningProfiles'] = {metadata['CFBundleIdentifier']: profile}
Path(output).write_bytes(plistlib.dumps(options))
PY
    xcodebuild -exportArchive -archivePath "$archive_path" -exportOptionsPlist "$options" \
      -exportPath "$export_path" -allowProvisioningUpdates \
      ${provisioning_auth[@]+"${provisioning_auth[@]}"} "$@"
    ;;
  *) echo 'Usage: scripts/testflight.sh archive|export|upload [ios|macos] [xcodebuild arguments]' >&2; exit 2 ;;
esac
