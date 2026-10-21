#!/bin/zsh
# Small checks during development; one complete check/package pass at completion.
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
MODE="${1:-metadata}"
if (( $# )); then shift; fi
case "$MODE" in
  metadata|core|ui)
    python3 scripts/version.py check
    python3 scripts/sync-formats.py --check
    case "$MODE" in
      core) zsh scripts/test.sh "$@" ;;
      ui) swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release -debug-info-format none ;;
    esac
    ;;
  release)
    zsh scripts/ci-checks.sh
    zsh scripts/build-app.sh
    ;;
  *) echo 'Usage: zsh scripts/check.sh metadata|core [--filter Suite]|ui|release' >&2; exit 2 ;;
esac
