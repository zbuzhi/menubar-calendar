#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --product CalendarCoreChecks --disable-sandbox -debug-info-format none --cache-path "$PWD/.build/shared-cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --manifest-cache local
.build/debug/CalendarCoreChecks
