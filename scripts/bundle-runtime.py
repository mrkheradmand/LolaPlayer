"""Bundle the dependency closure of an already installed, open-source libmpv.

LUMEN_MPV_LIBRARY can select another runtime. No Elmedia binaries are copied.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys

app = Path(sys.argv[1])
candidates = [os.environ.get('LUMEN_MPV_LIBRARY', ''), '/opt/homebrew/lib/libmpv.2.dylib',
              '/usr/local/lib/libmpv.2.dylib', '/Applications/IINA.app/Contents/Frameworks/libmpv.2.dylib']
runtime = next((Path(p) for p in candidates if p and Path(p).is_file()), None)
if runtime is None:
    raise SystemExit('No libmpv runtime found. Set LUMEN_MPV_LIBRARY to an installed libmpv.2.dylib.')
destination = app / 'Contents/Frameworks'
destination.mkdir(parents=True, exist_ok=True)
pending, copied = [runtime], set()
while pending:
    library = pending.pop()
    if library.name in copied:
        continue
    copied.add(library.name)
    target = destination / library.name
    shutil.copy2(library.resolve(), target)
    target.chmod(0o755)
    output = subprocess.check_output(['otool', '-L', str(library)], text=True)
    for line in output.splitlines()[1:]:
        dependency = line.strip().split(' (compatibility')[0]
        if not dependency or dependency.startswith(('/System/', '/usr/lib/')) or ' (architecture ' in dependency:
            continue
        if dependency.startswith(('@rpath/', '@loader_path/')):
            name = dependency.split('/', 1)[1]
            resolved = library.parent / name
        elif dependency.startswith('/'):
            resolved = Path(dependency)
        else:
            continue
        if resolved.name.startswith('libswift'):
            continue
        if not resolved.exists():
            raise SystemExit(f'Missing dependency: {dependency} (from {library})')
        if resolved.name != library.name:
            pending.append(resolved)
        if dependency != '@rpath/' + resolved.name:
            subprocess.run(['install_name_tool', '-change', dependency, '@rpath/' + resolved.name, str(target)], check=True)
    subprocess.run(['install_name_tool', '-id', '@rpath/' + library.name, str(target)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True, capture_output=True)
notice = app / 'Contents/Resources/Runtime.txt'
notice.write_text(f'Playback runtime: libmpv and its shared-library dependencies.\nLocal source: {runtime}\n'
                  'mpv: https://mpv.io/ (GPLv2 or later for this runtime).\n'
                  'FFmpeg: https://ffmpeg.org/ ; libass: https://github.com/libass/libass\n'
                  'This build is for local use. Before redistribution, supply all applicable licenses and corresponding source.\n')
print(f'Bundled {len(copied)} playback libraries from {runtime.parent}')
