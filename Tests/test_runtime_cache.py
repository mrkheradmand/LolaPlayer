import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('runtime_cache', ROOT/'scripts/runtime_cache.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class RuntimeCacheTests(unittest.TestCase):
    def test_content_and_build_context_invalidate_key(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)/'libmpv.dylib'
            source.write_bytes(b'first')
            first = cache.fingerprint([source], {'compiler': 'one'})
            source.write_bytes(b'other')  # Same size; mtime/size alone is insufficient.
            self.assertNotEqual(first, cache.fingerprint([source], {'compiler': 'one'}))
            self.assertNotEqual(cache.fingerprint([source], {'compiler': 'one'}),
                                cache.fingerprint([source], {'compiler': 'two'}))

    def test_corruption_and_missing_files_reject_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            staging = root/'staging'; staging.mkdir()
            (staging/'libmpv.dylib').write_bytes(b'validated runtime')
            capabilities = {'libraries': ['libmpv.dylib'], 'modern_runtime': True}
            entry = root/'cache'/'key'
            cache.save(entry, staging, capabilities)
            self.assertEqual(cache.load(entry), capabilities)
            (entry/'libmpv.dylib').write_bytes(b'corrupted runtime')
            self.assertIsNone(cache.load(entry))
            cache.save(entry, staging, capabilities)
            self.assertEqual(cache.load(entry), capabilities)
            (entry/'libmpv.dylib').unlink()
            self.assertIsNone(cache.load(entry))

    def test_invalid_manifest_is_a_miss(self):
        with tempfile.TemporaryDirectory() as temporary:
            entry = Path(temporary)
            for invalid in ['{broken', '{}', '[]', '{"files": [], "capabilities": {}}']:
                (entry/'manifest.json').write_text(invalid)
                self.assertIsNone(cache.load(entry))
