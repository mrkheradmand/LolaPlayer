#!/usr/bin/env python3
"""Keep app metadata, README and newest-first release notes in sync."""
import argparse
from datetime import datetime
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parent.parent
INFO = ROOT / 'Resources/Info.plist'
NOTES = ROOT / 'versions.md'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'patch', 'minor', 'major'])
    for category in ['added', 'modified', 'removed']:
        parser.add_argument('--' + category, action='append', default=[])
    args = parser.parse_args()
    info = plistlib.loads(INFO.read_bytes())
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    if args.action == 'check':
        notes = NOTES.read_text()
        heading = re.search(r'^## ([0-9.]+) \(build (\d+)\)', notes, re.M)
        if not heading or heading.groups() != (version, build):
            raise SystemExit('Version metadata and newest versions.md entry disagree')
        for filename in ['README.md', 'README-technical.md']:
            if f'| Version | {version}, build {build} |' not in (ROOT/filename).read_text():
                raise SystemExit(f'{filename} version is out of date')
        print(f'Lola Player {version} (build {build})')
        return
    if not any([args.added, args.modified, args.removed]):
        parser.error('Describe the change using --added, --modified or --removed')
    components = [int(x) for x in version.split('.')]
    components += [0] * (3-len(components))
    index = {'major': 0, 'minor': 1, 'patch': 2}[args.action]
    components[index] += 1
    for i in range(index+1, 3):
        components[i] = 0
    version = '.'.join(map(str, components))
    build = str(int(build)+1)
    # Preserve plist formatting so only the two version lines change.
    text = INFO.read_text()
    for key, value in [('CFBundleShortVersionString', version), ('CFBundleVersion', build)]:
        text = re.sub(r'(<key>'+key+r'</key>\s*<string>)[^<]+', lambda m: m[1]+value, text)
    INFO.write_text(text)
    for filename in ['README.md', 'README-technical.md']:
        readme = ROOT/filename
        readme.write_text(re.sub(r'\| Version \|[^\n]+', f'| Version | {version}, build {build} |', readme.read_text()))
    entry = f'## {version} (build {build}) — {datetime.now().astimezone():%Y-%m-%d}\n\n'
    for category in ['Added', 'Modified', 'Removed']:
        entry += f'### {category}\n\n'
        entry += ''.join(f'- {item}\n' for item in (getattr(args, category.lower()) or ['None.']))+'\n'
    old = NOTES.read_text() if NOTES.exists() else '# Lola Player versions\n\n'
    prefix = '# Lola Player versions\n\n'
    NOTES.write_text(prefix+entry+old.removeprefix(prefix))
    print(f'Lola Player {version} (build {build})')

if __name__ == '__main__':
    main()
