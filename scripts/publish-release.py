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


def api(run, endpoint, *, method='GET', payload=None, paginate=False):
    args = ['gh', 'api', endpoint, '--method', method]
    options = {'capture_output': True, 'text': True}
    if paginate:
        args.extend(['--paginate', '--slurp'])
    if payload is not None:
        args.extend(['--input', '-'])
        options['input'] = json.dumps(payload)
    response = run(args, **options)
    if response.returncode:
        detail = response.stderr.strip() or response.stdout.strip() or f'exit status {response.returncode}'
        raise RuntimeError(f'GitHub API {method} {endpoint} failed: {detail}')
    return json.loads(response.stdout)


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
    # By-tag REST lookup returns published releases, so discover drafts by list.
    releases = f'repos/{repo}/releases'
    pages = api(run, releases+'?per_page=100', paginate=True)
    matches = [item for page in pages for item in page if item['tag_name'] == tag]
    if len(matches) > 1:
        raise ValueError(f'Multiple releases match {tag}; refusing to choose a draft')
    existing = matches[0] if matches else None
    if existing is not None and not existing['draft']:
        raise ValueError(f'{tag} is already published; existing assets will not be overwritten')
    if existing is None:
        # Preserve --verify-tag behavior: never create a tag implicitly.
        api(run, f'repos/{repo}/git/ref/tags/{tag}')
        existing = api(run, releases, method='POST', payload={
            'tag_name': tag, 'name': f'Lola Player {result["version"]}',
            'body': result['notes'], 'draft': True})
    release_id = existing['id']
    if not isinstance(release_id, int) or existing['tag_name'] != tag or not existing['draft']:
        raise ValueError('GitHub did not return the expected draft release')
    endpoint = f'{releases}/{release_id}'
    # A failed upload leaves a draft. Rerunning safely replaces that draft's assets.
    run(['gh', 'release', 'upload', tag, *map(str, assets), '--repo', repo, '--clobber'], check=True)
    uploaded = api(run, endpoint)
    if uploaded['tag_name'] != tag or not uploaded['draft']:
        raise ValueError('Release changed while uploading; refusing to publish')
    remote = {item['name']: item for item in uploaded['assets']}
    for path in assets:
        item = remote.get(path.name)
        if not item or item['state'] != 'uploaded' or item['size'] != path.stat().st_size:
            raise ValueError(f'Release asset was not uploaded completely: {path.name}')
        with path.open('rb') as handle:
            expected = 'sha256:'+hashlib.file_digest(handle, 'sha256').hexdigest()
        if item.get('digest') != expected:
            raise ValueError(f'Release asset digest does not match: {path.name}')
    published = api(run, endpoint, method='PATCH', payload={
        'draft': False, 'name': f'Lola Player {result["version"]}', 'body': result['notes']})
    if published['draft'] or published['tag_name'] != tag:
        raise ValueError('GitHub did not confirm publication of the expected release')
    print(f'Published {tag} with verified DMG and checksum')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--repo', required=True)
    args = parser.parse_args()
    try:
        publish(ROOT, args.tag, args.repo)
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Release publishing failed: {error}') from error


if __name__ == '__main__':
    main()
