import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT/f'scripts/{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


metadata = load('release-metadata')
publisher = load('publish-release')
runtime = load('fetch-runtime')


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root/'Resources').mkdir()
        (self.root/'Resources/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '8'}))
        (self.root/'README.md').write_text('| Version | 1.2.3, build 8 |\n')
        (self.root/'versions.md').write_text(
            '# Lola Player versions\n\n## 1.2.3 (build 8) — Today\n\n'
            '### Added\n\n- Feature.\n\n### Modified\n\n- Fix.\n\n### Removed\n\n- None.\n\n'
            '## 1.2.2 (build 7)\n\nOlder notes.\n')
        self.assets = self.root/'dist/releases'
        self.assets.mkdir(parents=True)
        self.dmg = self.assets/'LolaPlayer-1.2.3-macOS-arm64.dmg'
        self.dmg.write_bytes(b'test image')
        self.checksum = self.assets/'SHA256SUMS.txt'
        self.checksum.write_text(f'{hashlib.sha256(self.dmg.read_bytes()).hexdigest()}  {self.dmg.name}\n')
        self.calls = []

    def fake_gh(self, *, existing=False, published=False, upload_failure=False,
                missing_asset=False, bad_digest=False, auth_failure=False):
        queries = 0

        def run(args, **kwargs):
            nonlocal queries
            self.calls.append(args)
            if args[1] == 'api':
                queries += 1
                if queries == 1 and auth_failure:
                    return subprocess.CompletedProcess(args, 1, '', 'HTTP 401: Bad credentials')
                if queries == 1 and not existing:
                    return subprocess.CompletedProcess(args, 1, '', 'HTTP 404: Not Found')
                paths = [self.dmg] if missing_asset else [self.dmg, self.checksum]
                assets = [{'name': p.name, 'state': 'uploaded', 'size': p.stat().st_size,
                           'digest': 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
                if bad_digest:
                    assets[0]['digest'] = 'sha256:wrong'
                return subprocess.CompletedProcess(args, 0, json.dumps({'draft': not published, 'assets': assets}), '')
            if args[2] == 'upload' and upload_failure:
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0, '', '')
        return run

    def publish(self, **options):
        publisher.publish(self.root, 'v1.2.3', 'owner/repo', run=self.fake_gh(**options))

    def test_notes_are_only_for_matching_latest_version(self):
        result = metadata.metadata(self.root, 'v1.2.3')
        self.assertIn('- Feature.', result['notes'])
        self.assertNotIn('Older notes.', result['notes'])
        for tag in ['v1.2.2', '1.2.3', 'v1.2.3-beta', 'v01.2.3']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                metadata.metadata(self.root, tag)
        (self.root/'README.md').write_text('Stale version')
        with self.assertRaises(ValueError):
            metadata.metadata(self.root, 'v1.2.3')

    def test_stale_notes_and_missing_categories_are_rejected(self):
        notes = self.root/'versions.md'
        original = notes.read_text()
        for modified in [original.replace('build 8', 'build 9'), original.replace('### Removed', '### Other')]:
            notes.write_text(modified)
            with self.assertRaises(ValueError):
                metadata.metadata(self.root, 'v1.2.3')

    def test_new_release_publishes_after_verified_upload(self):
        self.publish()
        commands = [call[2] for call in self.calls if call[1] == 'release']
        self.assertEqual(commands, ['create', 'upload', 'edit'])
        self.assertIn('--draft', self.calls[1])
        self.assertIn('--verify-tag', self.calls[1])
        self.assertIn('--draft=false', self.calls[-1])

    def test_failed_upload_never_publishes_and_draft_can_be_retried(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish(upload_failure=True)
        self.assertFalse(any('--draft=false' in call for call in self.calls))
        self.calls.clear()
        self.publish(existing=True)
        self.assertFalse(any('create' in call for call in self.calls))
        self.assertIn('--clobber', self.calls[1])
        self.assertIn('--draft=false', self.calls[-1])

    def test_existing_published_release_and_auth_errors_are_untouched(self):
        for options in [{'existing': True, 'published': True}, {'auth_failure': True}]:
            self.calls.clear()
            with self.assertRaises((ValueError, RuntimeError)):
                self.publish(**options)
            self.assertEqual(len(self.calls), 1)

    def test_incomplete_or_corrupt_remote_assets_never_publish(self):
        for options in [{'missing_asset': True}, {'bad_digest': True}]:
            self.calls.clear()
            with self.assertRaises(ValueError):
                self.publish(**options)
            self.assertFalse(any('--draft=false' in call for call in self.calls))

    def test_local_checksum_or_filename_mismatch_never_contacts_github(self):
        for text in ['wrong checksum', self.checksum.read_text().replace(self.dmg.name, 'another.dmg')]:
            self.checksum.write_text(text)
            with self.assertRaises(ValueError):
                self.publish()
        self.assertEqual(self.calls, [])

    def test_runtime_tampering_is_rejected(self):
        digest = hashlib.sha256(self.dmg.read_bytes()).hexdigest()
        runtime.verify(self.dmg, digest)
        self.dmg.write_bytes(b'tampered')
        with self.assertRaises(ValueError):
            runtime.verify(self.dmg, digest)


if __name__ == '__main__':
    unittest.main()
