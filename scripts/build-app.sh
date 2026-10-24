#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
architectures=(--arch arm64 --arch x86_64)
if [[ "${1:-}" == "--native" ]]; then architectures=(); fi
swift build "${architectures[@]}" -c release --product PerpetualCalendar --disable-sandbox -debug-info-format none --cache-path "$PWD/.build/shared-cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --manifest-cache local
app="$PWD/dist/不知时日历.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
bin_path=$(swift build "${architectures[@]}" -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/shared-cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --manifest-cache local)
cp "$bin_path/PerpetualCalendar" "$app/Contents/MacOS/PerpetualCalendar.new"
mv -f "$app/Contents/MacOS/PerpetualCalendar.new" "$app/Contents/MacOS/PerpetualCalendar"
python3 scripts/build-icon.py "$app"
cp Resources/HolidayData-LICENSE.txt "$app/Contents/Resources/HolidayData-LICENSE.txt"
framework="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$framework" ]]; then print -u2 'Sparkle framework missing; run swift package resolve.'; exit 1; fi
mkdir -p "$app/Contents/Frameworks"
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
cp -f .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
# Keep vendor signatures on the framework/helpers for local ad-hoc builds. Developer ID
# distribution must re-sign nested code inside-out before signing the outer bundle.
identity="${CALENDAR_SIGN_IDENTITY:--}"
if [[ "$identity" != '-' ]]; then
    nested="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    for code in "$nested/XPCServices/Downloader.xpc" "$nested/XPCServices/Installer.xpc" \
                "$nested/Autoupdate" "$nested/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"; do
        codesign --force --options runtime --timestamp --sign "$identity" "$code"
    done
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
lipo -archs "$app/Contents/MacOS/PerpetualCalendar"
print "已构建：$app"
