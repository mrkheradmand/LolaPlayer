#!/usr/bin/env python3
"""Keep Finder registrations aligned with folder discovery and auxiliary inputs."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parent.parent
source = (root/'Sources/PlayerCore/PlaybackOrder.swift').read_text()
block = source.split('public static let fileExtensions: Set<String> = [', 1)[1].split(']', 1)[0]
extensions = set(re.findall(r'"([a-z0-9]+)"', block))
extensions.update(['m3u', 'm3u8', 'srt', 'ass', 'ssa', 'vtt', 'sub', 'iso'])
plist = root/'Resources/Info.plist'
text = plist.read_text()
pattern = r'(<key>CFBundleTypeExtensions</key><array>).*?(</array>)'
expected = '\n'+''.join(f'<string>{item}</string>' for item in sorted(extensions))+'\n'
updated = re.sub(pattern, lambda match: match[1]+expected+match[2], text, count=1, flags=re.S)
if '--check' in sys.argv:
    if text != updated:
        raise SystemExit('Finder extensions are stale; run python3 scripts/sync-formats.py')
else:
    plist.write_text(updated)
print(f'{len(extensions)} Finder extensions synchronized')
