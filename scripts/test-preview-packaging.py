#!/usr/bin/env python3
"""Package synthetic archives and prove the originals remain untouched."""
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile


class PackagingTests(unittest.TestCase):
    def test_archive_copies(self):
        source = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / 'scripts'
            scripts.mkdir()
            for name in ('build-config.sh', 'preview-release.sh'):
                shutil.copy(source / name, scripts / name)
            # Any attempt to compile instead of packaging an archive must fail.
            (scripts / 'build.sh').write_text('#!/bin/bash\nexit 99\n')
            (scripts / 'build.sh').chmod(0o755)
            commands = root / 'commands'
            commands.mkdir()
            codesign = commands / 'codesign'
            codesign.write_text('''#!/usr/bin/env python3
from pathlib import Path
import sys
path = Path(sys.argv[-1])
if path.name != 'FixtureBinary':
    sys.exit(1)
if '--remove-signature' in sys.argv:
    path.write_bytes(b'unsigned fixture')
''')
            codesign.chmod(0o755)
            env = dict(os.environ, CI='true', APP_VERSION='1.2.3', BUILD_NUMBER='4',
                       PATH=f'{commands}:{os.environ["PATH"]}')
            def snapshot(path):
                return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in path.rglob('*') if p.is_file()}
            for platform in ('ios', 'macos'):
                archive = root / f'build-release/Slipstream-{platform}.xcarchive'
                app = archive / 'Products/Applications/Fixture.app'
                app.mkdir(parents=True)
                (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {
                    'ApplicationPath': 'Applications/Fixture.app',
                    'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '4'}}))
                content = app if platform == 'ios' else app / 'Contents'
                (content / '_CodeSignature').mkdir(parents=True)
                (content / '_CodeSignature/CodeResources').write_text('original signature')
                (content / 'FixtureBinary').write_bytes(b'signed fixture')
                profile = content / ('embedded.mobileprovision' if platform == 'ios' else 'embedded.provisionprofile')
                profile.write_text('original profile')
                before = snapshot(archive)
                result = subprocess.run(['bash', str(scripts / 'preview-release.sh'), platform],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(snapshot(archive), before)
            output = root / 'build-preview/v1.2.3-preview.4'
            with zipfile.ZipFile(next(output.glob('*.ipa'))) as ipa:
                self.assertIn('Payload/Slipstream.app/FixtureBinary', ipa.namelist())
                self.assertEqual(ipa.read('Payload/Slipstream.app/FixtureBinary'), b'unsigned fixture')
                self.assertFalse(any('_CodeSignature/' in n or n.endswith('embedded.mobileprovision')
                                     for n in ipa.namelist()))
            self.assertFalse((output / 'macos/Slipstream.app/Contents/embedded.provisionprofile').exists())
            self.assertEqual((output / 'macos/Slipstream.app/Contents/FixtureBinary').read_bytes(), b'signed fixture')
            result = subprocess.run(['bash', str(scripts / 'preview-release.sh'), 'macos'],
                                    env=dict(env, BUILD_NUMBER='5'), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Archive version/build does not match', result.stderr)
            self.assertFalse((root / 'build-preview/v1.2.3-preview.5').exists())


if __name__ == '__main__':
    unittest.main()
