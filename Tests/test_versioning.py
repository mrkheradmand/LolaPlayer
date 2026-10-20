import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

class VersioningTests(unittest.TestCase):
    def test_bump_synchronizes_metadata_and_preserves_notes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'scripts').mkdir(); (root/'Resources').mkdir()
            shutil.copy2(ROOT/'scripts/version.py', root/'scripts/version.py')
            (root/'Resources/Info.plist').write_text('<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>1.2.9</string><key>CFBundleVersion</key><string>7</string></dict></plist>')
            (root/'README.md').write_text('| Version | 1.2.9, build 7 |\n')
            old='# Lola Player versions\n\n## 1.2.9 (build 7)\n\nPrevious notes.\n'
            (root/'versions.md').write_text(old)
            result=subprocess.run(['python3',str(root/'scripts/version.py'),'minor','--added','New decoder','--modified','Playback fix'],capture_output=True,text=True,check=True)
            self.assertIn('1.3.0 (build 8)', result.stdout)
            metadata=plistlib.loads((root/'Resources/Info.plist').read_bytes())
            self.assertEqual(metadata['CFBundleShortVersionString'],'1.3.0')
            notes=(root/'versions.md').read_text()
            self.assertLess(notes.index('## 1.3.0'),notes.index('## 1.2.9'))
            self.assertIn('### Removed\n\n- None.',notes)
            self.assertIn('Previous notes.',notes)
            subprocess.run(['python3',str(root/'scripts/version.py'),'check'],check=True,capture_output=True)
            (root/'README.md').write_text('Outdated README')
            stale=subprocess.run(['python3',str(root/'scripts/version.py'),'check'],capture_output=True)
            self.assertNotEqual(stale.returncode,0)

if __name__=='__main__': unittest.main()
