#!/bin/bash
set -euo pipefail
# shellcheck source=scripts/build-config.sh
source "$(dirname "$0")/build-config.sh"

platform="${1:-}"
[[ $# -gt 0 ]] && shift
configuration="${SLIPSTREAM_CONFIGURATION:-Debug}"
signing=()
case "$platform" in
  macos)
    scheme=Slipstream
    destination='generic/platform=macOS'
    derived_data="${SLIPSTREAM_DERIVED_DATA_PATH:-build}"
    if [[ "${1:-}" == --ad-hoc ]]; then
      shift; signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-)
    elif [[ "${1:-}" == --unsigned ]]; then
      shift; signing=(CODE_SIGNING_ALLOWED=NO)
    elif [[ ! -f Config/Local.xcconfig && -z "${APPLE_SIGNING_IDENTITY:-}" ]]; then
      echo 'Set up Config/Local.xcconfig, export signing variables, or use --ad-hoc for a disposable build.' >&2
      exit 1
    fi
    ;;
  ios)
    scheme=Slipstream-iOS
    destination='generic/platform=iOS Simulator'
    derived_data="${SLIPSTREAM_DERIVED_DATA_PATH:-build-ios}"
    # Simulator Keychain access requires a signed app. Ad-hoc is enough here.
    signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-)
    ;;
  ios-device)
    scheme=Slipstream-iOS
    destination='generic/platform=iOS'
    derived_data="${SLIPSTREAM_DERIVED_DATA_PATH:-build-ios-device}"
    ;;
  *) echo 'Usage: scripts/build.sh macos [--ad-hoc|--unsigned] | ios | ios-device [xcodebuild arguments]' >&2; exit 2 ;;
esac

xcodebuild -project Slipstream.xcodeproj -scheme "$scheme" -configuration "$configuration" \
  -destination "$destination" -derivedDataPath "$derived_data" -jobs "${BUILD_JOBS:-2}" \
  ${build_settings[@]+"${build_settings[@]}"} ${signing[@]+"${signing[@]}"} "$@" build
