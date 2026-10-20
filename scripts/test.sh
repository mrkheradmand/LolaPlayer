#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
SWIFT_TOOLCHAIN="$(dirname "$(xcrun --find swiftc)")/.."
TESTING_PLUGIN="$SWIFT_TOOLCHAIN/lib/swift/host/plugins/testing/libTestingMacros.dylib"
swift test --disable-sandbox --cache-path "$PWD/.build/cache" --scratch-path "$PWD/.build/tests" -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN"
