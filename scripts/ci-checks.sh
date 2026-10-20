#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ "$(uname -m)" == arm64 ]] || { echo 'An Apple Silicon runner is required.' >&2; exit 1; }
python3 scripts/check-toolchain.py
python3 scripts/version.py check
python3 scripts/sync-formats.py --check
python3 -m unittest discover -s Tests -p 'test_*.py'
zsh scripts/test.sh
