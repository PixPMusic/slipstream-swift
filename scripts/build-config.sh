#!/bin/bash
# Shared by local build/distribution scripts; not a standalone command.
# shellcheck disable=SC2034
set -euo pipefail

SLIPSTREAM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$SLIPSTREAM_ROOT"

# This is a trusted, local shell file. CI uses its environment, never a dotenv file.
# Preserve explicit caller overrides when loading local defaults.
if [[ "${CI:-}" != true && -f .env.local ]]; then
  saved_overrides=()
  for key in SLIPSTREAM_BUNDLE_ID SLIPSTREAM_KEYCHAIN_SERVICE APPLE_TEAM_ID \
    APPLE_SIGNING_IDENTITY APP_VERSION BUILD_NUMBER BUILD_JOBS IOS_PROVISIONING_PROFILE SLIPSTREAM_DERIVED_DATA_PATH \
    SLIPSTREAM_CONFIGURATION SLIPSTREAM_ARCHIVE_PATH SLIPSTREAM_EXPORT_PATH \
    APP_STORE_CONNECT_KEY_PATH APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID; do
    if [[ -n "${!key+x}" ]]; then saved_overrides+=("$key=${!key}"); fi
  done
  set -a
  # shellcheck source=/dev/null
  source .env.local
  set +a
  for entry in ${saved_overrides[@]+"${saved_overrides[@]}"}; do export "${entry?}"; done
fi

build_settings=()
signing_identity_setting=CODE_SIGN_IDENTITY
if [[ -n "${IOS_PROVISIONING_PROFILE:-}" ]]; then
  signing_identity_setting=SLIPSTREAM_CODE_SIGN_IDENTITY
fi
for mapping in SLIPSTREAM_BUNDLE_ID:SLIPSTREAM_BUNDLE_ID \
  SLIPSTREAM_KEYCHAIN_SERVICE:SLIPSTREAM_KEYCHAIN_SERVICE \
  APPLE_TEAM_ID:DEVELOPMENT_TEAM "APPLE_SIGNING_IDENTITY:$signing_identity_setting" \
  APP_VERSION:MARKETING_VERSION BUILD_NUMBER:CURRENT_PROJECT_VERSION; do
  name="${mapping%%:*}"
  setting="${mapping#*:}"
  if [[ -n "${!name:-}" ]]; then build_settings+=("$setting=${!name}"); fi
done
if [[ -n "${IOS_PROVISIONING_PROFILE:-}" ]]; then
  build_settings+=(SLIPSTREAM_CODE_SIGN_STYLE=Manual "SLIPSTREAM_PROVISIONING_PROFILE=$IOS_PROVISIONING_PROFILE")
fi

provisioning_auth=()
if [[ -n "${APP_STORE_CONNECT_KEY_PATH:-}${APP_STORE_CONNECT_KEY_ID:-}${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  : "${APP_STORE_CONNECT_KEY_PATH:?Set the API key path, ID and issuer together}"
  : "${APP_STORE_CONNECT_KEY_ID:?Set the API key path, ID and issuer together}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?Set the API key path, ID and issuer together}"
  [[ -r "$APP_STORE_CONNECT_KEY_PATH" ]] || { echo 'App Store Connect key file is not readable.' >&2; exit 1; }
  provisioning_auth=(-authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH" \
    -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")
fi
