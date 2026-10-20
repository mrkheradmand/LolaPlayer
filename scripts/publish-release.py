#!/usr/bin/env python3
"""Publish only after both verified release assets have uploaded successfully."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('release_metadata', ROOT/'scripts/release-metadata.py')
release_metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_metadata)


def publish(root, tag, repo, run=subprocess.run):
    result = release_metadata.metadata(root, tag)
    directory = root/'dist/releases'
    dmg = directory/result['dmg']
    checksum = directory/'SHA256SUMS.txt'
    assets = [dmg, checksum]
    with dmg.open('rb') as handle:
        digest = hashlib.file_digest(handle, 'sha256').hexdigest()
    if checksum.read_text().strip() != f'{digest}  {dmg.name}':
        raise ValueError('DMG filename or checksum does not match SHA256SUMS.txt')
    notes = root/'.build/release/release-notes.md'
    notes.parent.mkdir(parents=True, exist_ok=True)
    notes.write_text(result['notes'])
    endpoint = f'repos/{repo}/releases/tags/{tag}'
    existing = run(['gh', 'api', endpoint], capture_output=True, text=True)
    if existing.returncode:
        if 'HTTP 404' not in existing.stderr:
            raise RuntimeError(f'Cannot check existing release: {existing.stderr.strip()}')
        run(['gh', 'release', 'create', tag, '--repo', repo, '--verify-tag', '--draft',
             '--title', f'Lola Player {result["version"]}', '--notes-file', str(notes)], check=True)
    elif not json.loads(existing.stdout)['draft']:
        raise ValueError(f'{tag} is already published; existing assets will not be overwritten')
    # A failed upload leaves a draft. Rerunning safely replaces that draft's assets.
    run(['gh', 'release', 'upload', tag, *map(str, assets), '--repo', repo, '--clobber'], check=True)
    uploaded = run(['gh', 'api', endpoint], capture_output=True, text=True, check=True)
    remote = {item['name']: item for item in json.loads(uploaded.stdout)['assets']}
    for path in assets:
        item = remote.get(path.name)
        if not item or item['state'] != 'uploaded' or item['size'] != path.stat().st_size:
            raise ValueError(f'Release asset was not uploaded completely: {path.name}')
        with path.open('rb') as handle:
            expected = 'sha256:'+hashlib.file_digest(handle, 'sha256').hexdigest()
        if item.get('digest') != expected:
            raise ValueError(f'Release asset digest does not match: {path.name}')
    run(['gh', 'release', 'edit', tag, '--repo', repo, '--draft=false',
         '--title', f'Lola Player {result["version"]}', '--notes-file', str(notes)], check=True)
    print(f'Published {tag} with verified DMG and checksum')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--repo', required=True)
    args = parser.parse_args()
    publish(ROOT, args.tag, args.repo)


if __name__ == '__main__':
    main()
