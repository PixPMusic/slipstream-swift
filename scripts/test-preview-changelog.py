#!/usr/bin/env python3
"""Synthetic git history tests; no GitHub access needed."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('changelog', Path(__file__).with_name('preview-changelog.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ChangelogTests(unittest.TestCase):
    def test_release_boundaries(self):
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                def git(*args):
                    return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL, text=True).strip()
                git('init', '-q')
                git('config', 'tag.gpgSign', 'false')
                git('config', 'commit.gpgSign', 'false')
                git('config', 'user.name', 'Fixture')
                git('config', 'user.email', 'fixture@example.invalid')
                git('commit', '--allow-empty', '-qm', 'First change')
                git('tag', 'v1.0.0')
                git('commit', '--allow-empty', '-qm', 'Preview change')
                git('tag', 'v1.1.0-preview.1')
                git('commit', '--allow-empty', '-qm', 'Latest change')
                stable = dict(draft=False, published_at='2026-01-01', tag_name='v1.0.0', html_url='https://example.invalid/stable')
                preview = dict(draft=False, published_at='2026-02-01', tag_name='v1.1.0-preview.1', html_url='https://example.invalid/preview')
                draft = dict(preview, draft=True, published_at='2026-03-01')
                first = module.changelog([], 'fixture/repo')
                self.assertIn('First change', first)
                self.assertIn('Latest change', first)
                result = module.changelog([stable, preview, draft], 'fixture/repo')
                self.assertIn('Latest change', result)
                self.assertNotIn('Preview change', result)
                self.assertNotIn('First change', result)
                git('checkout', '--orphan', 'unrelated')
                git('commit', '--allow-empty', '-qm', 'Unrelated')
                with self.assertRaises(subprocess.CalledProcessError):
                    module.changelog([stable], 'fixture/repo')
                with self.assertRaises(subprocess.CalledProcessError):
                    module.changelog([dict(stable, tag_name='missing')], 'fixture/repo')
            finally:
                os.chdir(original)


if __name__ == '__main__':
    unittest.main()
