#!/usr/bin/env python3
"""Download the pinned official runtime, verify it, and import its libraries."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def verify(path, expected):
    with path.open('rb') as handle:
        actual = hashlib.file_digest(handle, 'sha256').hexdigest()
    if actual != expected:
        raise ValueError(f'Runtime checksum mismatch: {path.name}')


def main():
    pin = json.loads((ROOT/'Runtime/pinned.json').read_text())
    downloads = ROOT/'.build/downloads'
    downloads.mkdir(parents=True, exist_ok=True)
    target = downloads/pin['filename']
    if target.exists():
        verify(target, pin['sha256'])
    else:
        temporary = target.with_suffix('.dmg.partial')
        try:
            subprocess.run(['curl', '--fail', '--location', '--retry', '3',
                            '--connect-timeout', '30', '--max-time', '600',
                            '--proto', '=https', '--proto-redir', '=https',
                            '--output', str(temporary), pin['url']], check=True)
            verify(temporary, pin['sha256'])
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    subprocess.run([sys.executable, str(ROOT/'scripts/import-runtime.py'), str(target)], check=True)


if __name__ == '__main__':
    main()
