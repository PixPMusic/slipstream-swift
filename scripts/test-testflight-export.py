#!/usr/bin/env python3
"""Verify manual export selects separate app and installer identities."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


class ExportTests(unittest.TestCase):
    def test_manual_export_identities(self):
        script = Path(__file__).resolve().with_name('testflight.sh')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / 'Fixture.xcarchive'
            archive.mkdir()
            app_identity = 'Apple Distribution: Fixture (TEAM123456)'
            (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {
                'Team': 'TEAM123456', 'CFBundleIdentifier': 'invalid.fixture.app',
                'SigningIdentity': app_identity}}))
            commands = root / 'commands'
            commands.mkdir()
            mock = '''#!/usr/bin/env python3
import json, os, pathlib, plistlib, sys
if pathlib.Path(sys.argv[0]).name == 'security':
    print(os.environ['FIXTURE_IDENTITIES'])
else:
    options = pathlib.Path(sys.argv[sys.argv.index('-exportOptionsPlist') + 1])
    pathlib.Path(os.environ['FIXTURE_OUTPUT']).write_text(json.dumps(plistlib.loads(options.read_bytes())))
'''
            for name in ('security', 'xcodebuild'):
                path = commands / name
                path.write_text(mock)
                path.chmod(0o755)
            output = root / 'options.json'
            env = dict(os.environ, CI='true', APPLE_TEAM_ID='TEAM123456',
                       APPLE_PROVISIONING_PROFILE='fixture-profile',
                       SLIPSTREAM_ARCHIVE_PATH=str(archive), FIXTURE_OUTPUT=str(output),
                       PATH=f'{commands}:{os.environ["PATH"]}')
            for key in ('APP_STORE_CONNECT_KEY_PATH', 'APP_STORE_CONNECT_KEY_ID', 'APP_STORE_CONNECT_ISSUER_ID'):
                env.pop(key, None)
            identity = 'A' * 40 + ' "3rd Party Mac Developer Installer: Fixture (TEAM123456)"'
            for platform, identities, success in [('ios', '', True), ('macos', identity, True),
                                                   ('macos', '', False), ('macos', identity + '\n' + identity, False)]:
                with self.subTest(platform=platform, identities=identities):
                    result = subprocess.run(['bash', str(script), 'export', platform],
                                            env=dict(env, FIXTURE_IDENTITIES=identities), capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, success, result.stderr)
                    if success:
                        options = json.loads(output.read_text())
                        self.assertEqual(options['provisioningProfiles'], {'invalid.fixture.app': 'fixture-profile'})
                        if platform == 'macos':
                            self.assertEqual(options['signingCertificate'], app_identity)
                            self.assertEqual(options['installerSigningCertificate'], 'A' * 40)
                        else:
                            self.assertEqual(options['signingCertificate'], 'Apple Distribution')
                            self.assertNotIn('installerSigningCertificate', options)


if __name__ == '__main__':
    unittest.main()
