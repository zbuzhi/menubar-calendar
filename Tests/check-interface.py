#!/usr/bin/env python3
"""Check the native app's panel interactions using an isolated defaults domain."""
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / '.build/clang-cache'))
target = platform.machine() + '-apple-macosx13.0'
with tempfile.TemporaryDirectory(prefix='calendar-interface-') as directory:
    root = Path(directory)
    app = root / 'Checks.app'
    macos = app / 'Contents/MacOS'
    frameworks = app / 'Contents/Frameworks'
    macos.mkdir(parents=True)
    frameworks.mkdir()
    vendor = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    subprocess.run(['ditto', str(vendor), str(frameworks / 'Sparkle.framework')], check=True)
    subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', '-target', target,
                    '-emit-module', '-emit-object', '-whole-module-optimization', '-module-name', 'CalendarCore',
                    '-emit-module-path', str(root / 'CalendarCore.swiftmodule'), '-o', str(root / 'CalendarCore.o'),
                    *map(str, sorted((ROOT / 'Sources/CalendarCore').glob('*.swift')))], check=True, env=env)
    subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', '-target', target,
                    '-D', 'CALENDAR_CHECKS', '-I', str(root), '-F', str(frameworks), '-framework', 'Sparkle',
                    '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', str(root / 'CalendarCore.o'),
                    *map(str, sorted((ROOT / 'Sources/PerpetualCalendar').glob('*.swift'))),
                    str(ROOT / 'Tests/InteractionChecks.swift'), '-o', str(macos / 'Checks')], check=True, env=env)
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='org.menubar-calendar.interface-checks.' + uuid.uuid4().hex,
                CFBundleExecutable='Checks', SUEnableAutomaticChecks=False)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run([str(macos / 'Checks')], check=True, env=env, timeout=30)
