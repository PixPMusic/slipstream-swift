#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'This helper is only for an isolated GitHub-hosted runner.' >&2; exit 1; }

python3 - "${1:-}" "${2:-ios}" <<'PY'
import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import uuid

mode, platform = sys.argv[1:]
if platform not in ('ios', 'macos'):
    sys.exit('Platform must be ios or macos.')
profile_variable = 'IOS_PROFILE_BASE64' if platform == 'ios' else 'MAC_PROFILE_BASE64'
profile_suffix = '.mobileprovision' if platform == 'ios' else '.provisionprofile'
directory = Path(os.environ['RUNNER_TEMP']) / 'slipstream-signing'
keychain = directory / 'build.keychain-db'
metadata_path = directory / 'cleanup.json'

def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout

if mode == 'cleanup':
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text())
        if metadata.get('keychains'):
            run('security', 'list-keychains', '-d', 'user', '-s', *metadata['keychains'])
        if keychain.exists():
            run('security', 'delete-keychain', str(keychain))
        if metadata.get('profile'):
            profile = Path(metadata['profile'])
            expected = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
            if profile.parent != expected or profile.suffix not in ('.mobileprovision', '.provisionprofile'):
                sys.exit('Refusing to remove an unexpected profile path.')
            profile.unlink(missing_ok=True)
    if directory.exists():
        shutil.rmtree(directory)
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write('APPLE_PROVISIONING_PROFILE=\n')
    sys.exit(0)

if mode not in ('install', 'install-developer-id'):
    sys.exit('Usage: ci-signing.sh install [ios|macos] | install-developer-id | cleanup')
required = ['DISTRIBUTION_P12_BASE64', 'ASC_PRIVATE_KEY',
            'ASC_KEY_ID', 'ASC_ISSUER_ID', 'APPLE_TEAM_ID', 'SLIPSTREAM_BUNDLE_ID']
if mode == 'install':
    required.append(profile_variable)
missing = [name for name in required if not os.environ.get(name)]
if missing:
    sys.exit('Configure these testflight environment values: ' + ', '.join(missing))
if not re.fullmatch(r'[A-Z0-9]{10}', os.environ['ASC_KEY_ID']):
    sys.exit('Invalid App Store Connect key ID.')
uuid.UUID(os.environ['ASC_ISSUER_ID'])
os.umask(0o077)
directory.mkdir(mode=0o700, exist_ok=False)
metadata = {'keychains': shlex.split(run('security', 'list-keychains', '-d', 'user').decode())}
metadata_path.write_text(json.dumps(metadata))

certificate = directory / 'distribution.p12'
certificate.write_bytes(base64.b64decode(os.environ['DISTRIBUTION_P12_BASE64'], validate=True))
profile_id = None
if mode == 'install':
    profile_source = directory / 'distribution.mobileprovision'
    profile_source.write_bytes(base64.b64decode(os.environ[profile_variable], validate=True))
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(profile_source)))
    team = os.environ['APPLE_TEAM_ID']
    bundle = os.environ['SLIPSTREAM_BUNDLE_ID']
    entitlements = profile['Entitlements']
    expected_platform = 'iOS' if platform == 'ios' else 'OSX'
    if expected_platform not in profile.get('Platform', []):
        sys.exit('The provisioning profile is for the wrong platform.')
    if team not in profile['TeamIdentifier'] or (entitlements.get('application-identifier') or entitlements.get('com.apple.application-identifier')) != f'{team}.{bundle}':
        sys.exit('The provisioning profile does not match the configured team and bundle ID.')
    if (entitlements.get('get-task-allow') or entitlements.get('com.apple.security.get-task-allow')) or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices'):
        sys.exit('An App Store distribution profile is required.')
    if profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        sys.exit('The provisioning profile has expired.')
    if profile.get('IsXcodeManaged'):
        sys.exit('CI requires a manually managed App Store profile, not an Xcode-managed profile.')
    profile_id = profile['UUID']
    uuid.UUID(profile_id)
    profile_path = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles' / f'{profile_id}{profile_suffix}'
    if profile_path.exists():
        sys.exit('Refusing to replace an existing provisioning profile.')
    metadata['profile'] = str(profile_path)
    metadata_path.write_text(json.dumps(metadata))
    profile_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(profile_source, profile_path)
password = secrets.token_urlsafe(32)
run('security', 'create-keychain', '-p', password, str(keychain))
run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
run('security', 'unlock-keychain', '-p', password, str(keychain))
# Installer export also needs unattended access to its private key.
run('security', 'import', str(certificate), '-P', os.environ.get('DISTRIBUTION_P12_PASSWORD', ''),
    '-k', str(keychain), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security',
    '-T', '/usr/bin/productbuild', '-T', '/usr/bin/productsign')
run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *metadata['keychains'])

api_key = directory / 'AuthKey.p8'
api_key.write_text(os.environ['ASC_PRIVATE_KEY'])
with open(os.environ['GITHUB_ENV'], 'a') as output:
    for name, value in {
        'APP_STORE_CONNECT_KEY_PATH': str(api_key),
        'APP_STORE_CONNECT_KEY_ID': os.environ['ASC_KEY_ID'],
        'APP_STORE_CONNECT_ISSUER_ID': os.environ['ASC_ISSUER_ID'],
    }.items():
        output.write(f'{name}={value}\n')
    if profile_id:
        output.write(f'APPLE_PROVISIONING_PROFILE={profile_id}\n')
print('Installed temporary distribution credentials; cleanup runs even on failure.')
PY
