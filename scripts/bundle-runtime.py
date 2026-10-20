"""Bundle and inspect a compatible libmpv/FFmpeg dependency closure.

Uses a workspace-staged runtime first; never mixes newer FFmpeg libraries into
an older libmpv ABI. LUMEN_MPV_LIBRARY selects an explicit source.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
explicit = os.environ.get('LUMEN_MPV_LIBRARY')
candidates = [explicit] if explicit else [
    str(root/'Runtime/Frameworks/libmpv.2.dylib'),
    '/opt/homebrew/lib/libmpv.2.dylib', '/usr/local/lib/libmpv.2.dylib',
    '/Applications/IINA.app/Contents/Frameworks/libmpv.2.dylib']
runtime = next((Path(p) for p in candidates if p and Path(p).is_file()), None)
if runtime is None:
    raise SystemExit('No runtime at the selected path. Import a newer runtime with scripts/import-runtime.py or set LUMEN_MPV_LIBRARY.')

def dependencies(library):
    output = subprocess.check_output(['otool', '-L', str(library)], text=True)
    for line in output.splitlines()[1:]:
        if ' (architecture ' in line or not line[:1].isspace():
            continue
        dependency = line.strip().split(' (compatibility')[0]
        if not dependency or dependency.startswith(('/System/', '/usr/lib/')):
            continue
        if dependency.startswith(('@rpath/', '@loader_path/')):
            resolved = library.parent/dependency.split('/', 1)[1]
        elif dependency.startswith('/'):
            resolved = Path(dependency)
        else:
            raise SystemExit(f'Unsupported library reference: {dependency} (from {library})')
        if resolved.name.startswith('libswift'):
            continue
        if not resolved.is_file():
            raise SystemExit(f'Missing dependency: {dependency} (from {library})')
        yield dependency, resolved

# Prepare the entire closure before replacing any playback library in the app.
with tempfile.TemporaryDirectory(prefix='lola-runtime-', dir=root/'.build') as temporary:
    staging = Path(temporary)
    pending, copied = [runtime], {}
    while pending:
        library = pending.pop()
        if library.name in copied:
            if copied[library.name] != library.resolve():
                raise SystemExit(f'Conflicting runtime libraries named {library.name}')
            continue
        copied[library.name] = library.resolve()
        target = staging/library.name
        architectures = subprocess.check_output(['lipo', '-archs', str(library)], text=True).split()
        if 'arm64' not in architectures:
            raise SystemExit(f'Playback dependency lacks arm64: {library}')
        if len(architectures) > 1:
            subprocess.run(['lipo', str(library), '-thin', 'arm64', '-output', str(target)], check=True)
        else:
            shutil.copy2(library.resolve(), target)
        target.chmod(0o755)
        for dependency, resolved in dependencies(library):
            if resolved.name != library.name:
                pending.append(resolved)
            replacement = '@rpath/'+resolved.name
            if dependency != replacement:
                subprocess.run(['install_name_tool', '-change', dependency, replacement, str(target)], check=True, capture_output=True)
        subprocess.run(['install_name_tool', '-id', '@rpath/'+library.name, str(target)], check=True, capture_output=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True, capture_output=True)
    probe = staging/'probe-runtime'
    subprocess.run(['clang', str(root/'scripts/probe-runtime.c'), '-Wl,-rpath,'+str(staging), '-o', str(probe)], check=True)
    result = subprocess.run([str(probe), str(staging/runtime.name)], capture_output=True, text=True, timeout=30, check=True)
    capabilities = json.loads(result.stdout)
    match = re.match(r'(\d+)\.(\d+)', capabilities['ffmpeg'])
    modern = bool(match and tuple(map(int, match.groups())) >= (8, 0)
                  and all(capabilities[key] for key in ['vvc', 'prores_raw', 'aac']))
    capabilities['xhe_aac'] = bool(match and tuple(map(int, match.groups())) >= (7, 1) and capabilities['aac'])
    capabilities['modern_runtime'] = bool(modern)
    capabilities['midi'] = 'macOS General MIDI synthesizer'
    capabilities['libraries'] = sorted(copied)
    if not modern and os.environ.get('LUMEN_ALLOW_LEGACY_RUNTIME') != '1':
        raise SystemExit(f'Runtime is FFmpeg {capabilities["ffmpeg"]}; this release requires FFmpeg 8 or newer with VVC, AAC/USAC and ProRes RAW decoders enabled. Import a compatible libmpv bundle. For feature testing only, LUMEN_ALLOW_LEGACY_RUNTIME=1 permits the old runtime without claiming the upgrade.')
    destination = app/'Contents/Frameworks'
    destination.mkdir(parents=True, exist_ok=True)
    for obsolete in destination.glob('*.dylib'):
        if obsolete.name not in copied:
            obsolete.unlink()
    for name in copied:
        shutil.copy2(staging/name, destination/name)
    resources = app/'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    (resources/'RuntimeCapabilities.json').write_text(json.dumps(capabilities, indent=2, sort_keys=True)+'\n')
    (resources/'Runtime.txt').write_text(
        f'Playback runtime: {capabilities["mpv"]}; FFmpeg {capabilities["ffmpeg"]}.\nLocal source: {runtime}\n'
        f'Modern runtime: {bool(modern)}; tracker decoder: {capabilities["tracker"]}.\n'
        'mpv: https://mpv.io/ ; FFmpeg: https://ffmpeg.org/ ; libass: https://github.com/libass/libass\n'
        'This build is for local use. Before redistribution, supply applicable licenses and corresponding source.\n')
    print(f'Bundled {len(copied)} arm64 playback libraries: {capabilities["mpv"]}, FFmpeg {capabilities["ffmpeg"]}; tracker={capabilities["tracker"]}')
