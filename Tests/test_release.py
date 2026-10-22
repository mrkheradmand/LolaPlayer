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
                missing_asset=False, bad_digest=False, auth_failure=False,
                verification_failure=False, previous='v1.2.2'):

        def run(args, **kwargs):
            self.calls.append(args)
            if args[1] == 'api':
                endpoint = args[2]
                method = args[args.index('--method')+1]
                if '/releases/tags/' in endpoint:
                    return subprocess.CompletedProcess(args, 1, '', 'HTTP 404: Not Found')
                if auth_failure:
                    return subprocess.CompletedProcess(args, 1, '', 'HTTP 401: Bad credentials')
                paths = [self.dmg] if missing_asset else [self.dmg, self.checksum]
                assets = [{'name': p.name, 'state': 'uploaded', 'size': p.stat().st_size,
                           'digest': 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
                if bad_digest:
                    assets[0]['digest'] = 'sha256:wrong'
                release = {'id': 42, 'tag_name': 'v1.2.3', 'draft': not published, 'assets': assets}
                if '?per_page=' in endpoint:
                    # Matching drafts must be found even on later pages.
                    data = [[{'id': 1, 'tag_name': previous, 'draft': False}], [release] if existing else []]
                elif '/git/ref/tags/' in endpoint:
                    data = {'ref': 'refs/tags/v1.2.3'}
                elif method == 'POST':
                    payload = json.loads(kwargs['input'])
                    self.assertTrue(payload['draft'])
                    self.assertEqual(payload['tag_name'], 'v1.2.3')
                    data = release
                elif endpoint.endswith('/releases/42'):
                    if method == 'GET' and verification_failure:
                        return subprocess.CompletedProcess(args, 1, '', 'HTTP 403: Resource not accessible by integration')
                    if method == 'PATCH':
                        self.assertFalse(json.loads(kwargs['input'])['draft'])
                        release['draft'] = False
                    data = release
                else:
                    self.fail(f'Unexpected GitHub API endpoint: {endpoint}')
                return subprocess.CompletedProcess(args, 0, json.dumps(data), '')
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
        self.assertEqual(commands, ['upload'])
        self.assertIn('/git/ref/tags/v1.2.3', self.calls[1][2])
        self.assertIn('POST', self.calls[2])
        self.assertIn('PATCH', self.calls[-1])
        self.assertTrue(self.calls[-1][2].endswith('/releases/42'))
        self.assertFalse(any('/releases/tags/' in call[2] for call in self.calls))

    def test_failed_upload_never_publishes_and_draft_can_be_retried(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish(upload_failure=True)
        self.assertFalse(any('PATCH' in call for call in self.calls))
        self.calls.clear()
        self.publish(existing=True)
        self.assertFalse(any('POST' in call for call in self.calls))
        self.assertIn('--clobber', self.calls[1])
        self.assertIn('PATCH', self.calls[-1])
        self.assertTrue(self.calls[-2][2].endswith('/releases/42'))

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
            self.assertFalse(any('PATCH' in call for call in self.calls))

    def test_draft_verification_api_error_is_visible_and_never_publishes(self):
        with self.assertRaisesRegex(RuntimeError, 'HTTP 403: Resource not accessible'):
            self.publish(existing=True, verification_failure=True)
        self.assertFalse(any('PATCH' in call for call in self.calls))

    def test_local_checksum_or_filename_mismatch_never_contacts_github(self):
        for text in ['wrong checksum', self.checksum.read_text().replace(self.dmg.name, 'another.dmg')]:
            self.checksum.write_text(text)
            with self.assertRaises(ValueError):
                self.publish()
        self.assertEqual(self.calls, [])

    def cumulative_fixture(self):
        (self.root/'versions.md').write_text(
            '# Lola Player versions\n\n## 1.2.3 (build 8) — Today\n\n'
            '### Added\n\n- Feature.\n\n### Modified\n\n- Current fix.\n\n### Removed\n\n- None.\n\n'
            '## 1.2.2 (build 7)\n\n### Added\n\n- feature\n- Earlier feature.\n\n'
            '### Modified\n\n- Older fix.\n\n### Removed\n\n- Old control.\n\n'
            '## 1.2.1 (build 6)\n\n### Added\n\n- Already published.\n\n'
            '### Modified\n\n- None.\n\n### Removed\n\n- None.\n')

    def test_combines_all_unreleased_versions_by_category(self):
        self.cumulative_fixture()
        result = metadata.combined_metadata(self.root, 'v1.2.3', 'v1.2.1')
        notes = result['notes']
        self.assertIn('Changes since **v1.2.1**', notes)
        self.assertIn('- Earlier feature.', notes)
        self.assertIn('- Current fix.', notes)
        self.assertIn('- Older fix.', notes)
        self.assertIn('### Removed\n\n- Old control.', notes)
        self.assertNotIn('Already published', notes)
        self.assertNotIn('- None', notes)
        self.assertEqual(notes.lower().count('- feature'), 1)

    def test_previous_release_selection_ignores_drafts_prereleases_and_newer_tags(self):
        pages = [[{'tag_name': 'v1.8.0', 'draft': False},
                  {'tag_name': 'v1.11.0', 'draft': True}],
                 [{'tag_name': 'v1.10.0', 'draft': False},
                  {'tag_name': 'v1.11.1', 'prerelease': True},
                  {'tag_name': 'v2.0.0'}, {'tag_name': 'v1.12.0'}, {'tag_name': 'invalid'}]]
        self.assertEqual(metadata.previous_release_tag(pages, 'v1.12.0'), 'v1.10.0')
        self.assertIsNone(metadata.previous_release_tag(pages, 'v1.0.0'))

    def test_release_discovery_reads_all_pages_and_reports_api_errors(self):
        def ok(args, **kwargs):
            self.assertIn('--paginate', args)
            self.assertIn('--slurp', args)
            return subprocess.CompletedProcess(args, 0, '[[{"tag_name": "v1.2.1"}], [{"tag_name": "v1.2.2"}]]', '')
        self.assertEqual(metadata.previous_release_tag(metadata.published_releases('owner/repo', run=ok), 'v1.2.3'), 'v1.2.2')
        def failed(args, **kwargs):
            return subprocess.CompletedProcess(args, 1, '', 'HTTP 401: Bad credentials')
        with self.assertRaisesRegex(RuntimeError, 'HTTP 401'):
            metadata.published_releases('owner/repo', run=failed)

    def test_first_release_includes_all_history_and_keeps_empty_categories(self):
        self.cumulative_fixture()
        result = metadata.combined_metadata(self.root, 'v1.2.3', None)
        self.assertIn('- Already published.', result['notes'])
        result = metadata.combined_metadata(self.root, 'v1.2.3', 'v1.2.2')
        self.assertIn('### Removed\n\n- None.', result['notes'])

    def test_missing_boundary_or_malformed_intermediate_entry_fails_safely(self):
        self.cumulative_fixture()
        for previous in ['v1.0.0', 'v1.2.3', 'invalid']:
            with self.subTest(previous=previous), self.assertRaises(ValueError):
                metadata.combined_metadata(self.root, 'v1.2.3', previous)
        notes = self.root/'versions.md'
        notes.write_text(notes.read_text().replace('### Modified\n\n- Older fix.', '### Other\n\n- Older fix.'))
        with self.assertRaisesRegex(ValueError, '1.2.2 is missing Modified'):
            metadata.combined_metadata(self.root, 'v1.2.3', 'v1.2.1')

    def test_new_and_resumed_drafts_publish_cumulative_notes(self):
        self.cumulative_fixture()
        for existing in [False, True]:
            with self.subTest(existing=existing):
                bodies = []
                fake = self.fake_gh(existing=existing, previous='v1.2.1')
                def record(args, **kwargs):
                    if 'input' in kwargs:
                        bodies.append(json.loads(kwargs['input']).get('body', ''))
                    return fake(args, **kwargs)
                publisher.publish(self.root, 'v1.2.3', 'owner/repo', run=record)
                self.assertTrue(bodies)
                for body in bodies:
                    self.assertIn('- Earlier feature.', body)
                    self.assertIn('- Old control.', body)
                    self.assertNotIn('Already published', body)
                self.assertIn('- Earlier feature.', (self.root/'.build/release/release-notes.md').read_text())

    def test_runtime_tampering_is_rejected(self):
        digest = hashlib.sha256(self.dmg.read_bytes()).hexdigest()
        runtime.verify(self.dmg, digest)
        self.dmg.write_bytes(b'tampered')
        with self.assertRaises(ValueError):
            runtime.verify(self.dmg, digest)


if __name__ == '__main__':
    unittest.main()
