#!/usr/bin/env python3
"""Require a version-matching tag and extract only the newest release notes."""
import argparse
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parent.parent


def metadata(root, tag):
    info = plistlib.loads((root/'Resources/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', tag) or tag != 'v'+version:
        raise ValueError(f'Tag {tag!r} must match app version v{version}')
    notes = (root/'versions.md').read_text()
    entries = list(re.finditer(r'^## (\S+) \(build (\d+)\)[^\n]*$', notes, re.M))
    if not entries or entries[0].groups() != (version, info['CFBundleVersion']):
        raise ValueError('Newest release notes must match the app version and build')
    section = notes[entries[0].start():entries[1].start() if len(entries) > 1 else len(notes)].strip()+'\n'
    for category in ['Added', 'Modified', 'Removed']:
        if f'### {category}\n' not in section:
            raise ValueError(f'Release notes are missing {category}')
    if f'| Version | {version}, build {info["CFBundleVersion"]} |' not in (root/'README.md').read_text():
        raise ValueError('README version does not match the app')
    return {'tag': tag, 'version': version, 'build': info['CFBundleVersion'],
            'dmg': f'LolaPlayer-{version}-macOS-arm64.dmg', 'notes': section}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    args = parser.parse_args()
    result = metadata(ROOT, args.tag)
    output = ROOT/'.build/release'
    output.mkdir(parents=True, exist_ok=True)
    (output/'release-notes.md').write_text(result['notes'])
    (output/'metadata.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f'Validated {result["tag"]} (build {result["build"]})')


if __name__ == '__main__':
    main()
