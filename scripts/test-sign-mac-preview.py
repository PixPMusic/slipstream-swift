#!/usr/bin/env python3
"""Exercise the signing pipeline with synthetic tools, without Apple credentials."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class SigningTests(unittest.TestCase):
    def test_acceptance_and_rejection(self):
        source = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / 'scripts'
            scripts.mkdir()
            for name in ('build-config.sh', 'sign-mac-preview.sh'):
                shutil.copy(source / name, scripts / name)
            app = root / 'build-preview/v1.2.3-preview.4/macos/Slipstream.app'
            (app / 'Contents/Frameworks/Fixture.framework').mkdir(parents=True)
            commands = root / 'commands'
            commands.mkdir()
            log = root / 'calls'
            mock = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(name + ' ' + ' '.join(sys.argv[1:]) + '\\n')
if name == 'security':
    print('  1) ' + 'A' * 40 + ' "Developer ID Application: Fixture (TEAM123456)"')
if name == 'xcrun' and sys.argv[1] == 'notarytool':
    print(json.dumps({'status': os.environ['NOTARY_STATUS']}))
'''
            for name in ('security', 'codesign', 'ditto', 'xcrun', 'spctl'):
                path = commands / name
                path.write_text(mock)
                path.chmod(0o755)
            key = root / 'key.p8'
            key.write_text('synthetic fixture')
            env = dict(os.environ, CI='true', APP_VERSION='1.2.3', BUILD_NUMBER='4',
                       APPLE_TEAM_ID='TEAM123456', APP_STORE_CONNECT_KEY_PATH=str(key),
                       APP_STORE_CONNECT_KEY_ID='fixture', APP_STORE_CONNECT_ISSUER_ID='fixture',
                       CALL_LOG=str(log), PATH=f'{commands}:{os.environ["PATH"]}')
            for status in ('Accepted', 'Invalid'):
                log.unlink(missing_ok=True)
                result = subprocess.run(['bash', str(scripts / 'sign-mac-preview.sh')],
                                        env=dict(env, NOTARY_STATUS=status), capture_output=True, text=True)
                calls = log.read_text()
                if status == 'Accepted':
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('--options runtime --timestamp', calls)
                    self.assertLess(calls.index('Fixture.framework'), calls.index('--entitlements'))
                    self.assertLess(calls.index('notarytool submit'), calls.index('stapler staple'))
                    self.assertLess(calls.index('stapler validate'), calls.index('spctl --assess'))
                    self.assertEqual(calls.count('ditto '), 2)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('stapler staple', calls)
                    self.assertEqual(calls.count('ditto '), 1)


if __name__ == '__main__':
    unittest.main()
