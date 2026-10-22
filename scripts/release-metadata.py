#!/usr/bin/env python3
"""Validate release metadata and combine categorized notes since the last published release."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

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


def version_tuple(tag):
    if not isinstance(tag, str) or not re.fullmatch(r'v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', tag):
        return None
    return tuple(map(int, tag[1:].split('.')))


def previous_release_tag(pages, current_tag):
    current = version_tuple(current_tag)
    if current is None:
        raise ValueError('Current release tag is invalid')
    candidates = []
    for page in pages:
        for release in page:
            tag = release.get('tag_name')
            version = version_tuple(tag)
            if version is not None and version < current and not release.get('draft', False) and not release.get('prerelease', False):
                candidates.append((version, tag))
    return max(candidates)[1] if candidates else None


def published_releases(repo, run=subprocess.run):
    response = run(['gh', 'api', f'repos/{repo}/releases?per_page=100', '--method', 'GET', '--paginate', '--slurp'],
                   capture_output=True, text=True)
    if response.returncode:
        raise RuntimeError('Cannot determine previous published release: '+(response.stderr.strip() or response.stdout.strip()))
    return json.loads(response.stdout)


def combined_metadata(root, tag, previous_tag):
    result = metadata(root, tag)
    previous = version_tuple(previous_tag) if previous_tag is not None else None
    if previous_tag is not None and (previous is None or previous >= version_tuple(tag)):
        raise ValueError('Previous release must be a valid version older than the current tag')
    notes = (root/'versions.md').read_text()
    entries = list(re.finditer(r'^## (\S+) \(build (\d+)\)[^\n]*$', notes, re.M))
    if previous_tag is not None and previous_tag[1:] not in [entry[1] for entry in entries]:
        raise ValueError(f'Previous published release {previous_tag} is missing from versions.md; refusing incomplete notes')
    categories = {name: [] for name in ['Added', 'Modified', 'Removed']}
    seen = {name: set() for name in categories}
    last_version = None
    for index, entry in enumerate(entries):
        if previous_tag is not None and entry[1] == previous_tag[1:]:
            break
        version = version_tuple('v'+entry[1])
        if version is None or (last_version is not None and version >= last_version) or (previous is not None and version <= previous):
            raise ValueError('versions.md entries must have unique versions in descending order')
        last_version = version
        section = notes[entry.end():entries[index+1].start() if index+1 < len(entries) else len(notes)]
        for category in categories:
            match = re.search(r'^### '+category+r'\s*\n(.*?)(?=^### |\Z)', section, re.M | re.S)
            if not match:
                raise ValueError(f'Version {entry[1]} is missing {category}')
            bullets = re.split(r'(?m)^- ', match[1])
            if bullets[0].strip():
                raise ValueError(f'Version {entry[1]} has unsupported text in {category}; use bullet points')
            for bullet in bullets[1:]:
                bullet = bullet.strip()
                key = re.sub(r'\s+', ' ', bullet).casefold().rstrip('.')
                if key in ('', 'none') or key in seen[category]:
                    continue
                seen[category].add(key)
                categories[category].append(bullet)
    heading = entries[0][0]+'\n\n'
    if previous_tag:
        heading += f'Changes since **{previous_tag}**.\n\n'
    result['notes'] = heading+''.join('### '+name+'\n\n'+''.join('- '+bullet+'\n' for bullet in (bullets or ['None.']))+'\n'
                                    for name, bullets in categories.items())
    result['previous_tag'] = previous_tag
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--repo', help='Resolve the previous published stable release through GitHub')
    source.add_argument('--previous-tag', help='Explicit previous release tag for an offline preview')
    args = parser.parse_args()
    if args.repo:
        previous = previous_release_tag(published_releases(args.repo), args.tag)
        result = combined_metadata(ROOT, args.tag, previous)
    elif args.previous_tag:
        result = combined_metadata(ROOT, args.tag, args.previous_tag)
    else:
        result = metadata(ROOT, args.tag)
    output = ROOT/'.build/release'
    output.mkdir(parents=True, exist_ok=True)
    (output/'release-notes.md').write_text(result['notes'])
    (output/'metadata.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f'Validated {result["tag"]} (build {result["build"]})')


if __name__ == '__main__':
    main()
