#!/usr/bin/env python3
"""Stage playback libraries from a local official IINA app or disk image."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]).expanduser().resolve()
mount = None
if source.suffix.lower() == '.dmg':
    pin = json.loads((ROOT/'Runtime/pinned.json').read_text())
    if source.name == pin['filename']:
        expected = pin['sha256']
        with source.open('rb') as handle:
            digest = hashlib.file_digest(handle, 'sha256').hexdigest()
        if digest != expected:
            raise SystemExit('Pinned official IINA disk-image checksum does not match')
    else:
        raise SystemExit('For other releases, extract the official app and pass its .app path')
    mount = Path(tempfile.mkdtemp(prefix='runtime-mount-', dir=ROOT/'.build'))
    subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(source)], check=True)
    source = mount/'IINA.app'
try:
    frameworks = source/'Contents/Frameworks' if source.suffix == '.app' else source
    if not (frameworks/'libmpv.2.dylib').is_file():
        raise SystemExit('Source does not contain libmpv.2.dylib')
    destination = ROOT/'Runtime/Frameworks'
    destination.mkdir(parents=True, exist_ok=True)
    for library in frameworks.glob('*.dylib'):
        shutil.copy2(library.resolve(), destination/library.name)
    (ROOT/'Runtime/source.json').write_text(json.dumps({'source': str(source), 'imported_from': sys.argv[1]}, indent=2)+'\n')
    print('Staged playback libraries. Run scripts/build-app.sh to inspect and package them.')
finally:
    if mount:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
        mount.rmdir()
