"""Content-addressed cache for inspected, signed playback libraries."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fingerprint(paths, context):
    inputs = [(str(Path(p).resolve()), digest(p)) for p in paths]
    return hashlib.sha256(json.dumps([sorted(inputs), context], sort_keys=True).encode()).hexdigest()


def load(directory):
    try:
        manifest = json.loads((directory/'manifest.json').read_text())
        files = manifest['files']
        capabilities = manifest['capabilities']
        if not isinstance(files, dict) or not isinstance(capabilities, dict):
            return None
        if not files or sorted(files) != sorted(capabilities['libraries']):
            return None
        for name, expected in files.items():
            if Path(name).name != name or not name.endswith('.dylib'):
                return None
            path = directory/name
            if path.is_symlink() or digest(path) != expected:
                return None
        return capabilities
    except (OSError, ValueError, KeyError, TypeError):
        return None


def save(directory, staging, capabilities):
    directory.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.runtime-', dir=directory.parent) as temporary:
        prepared = Path(temporary)/'entry'
        prepared.mkdir()
        files = {}
        for name in capabilities['libraries']:
            shutil.copy2(staging/name, prepared/name)
            files[name] = digest(prepared/name)
        (prepared/'manifest.json').write_text(json.dumps({'files': files, 'capabilities': capabilities}, sort_keys=True))
        if directory.exists():
            if load(directory) is not None:
                return
            shutil.rmtree(directory)
        try:
            prepared.rename(directory)
        except FileExistsError:
            pass  # Another successful packager published the same content first.
