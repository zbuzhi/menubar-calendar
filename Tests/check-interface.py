#!/usr/bin/env python3
"""Check optimized, stripped native app code using an isolated defaults domain."""
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
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
    subprocess.run(['swiftc', '-O', '-disable-sandbox', '-parse-as-library', '-swift-version', '5', '-target', target,
                    '-emit-module', '-emit-object', '-whole-module-optimization', '-module-name', 'CalendarCore',
                    '-emit-module-path', str(root / 'CalendarCore.swiftmodule'), '-o', str(root / 'CalendarCore.o'),
                    *map(str, sorted((ROOT / 'Sources/CalendarCore').glob('*.swift')))], check=True, env=env)
    subprocess.run(['swiftc', '-O', '-disable-sandbox', '-parse-as-library', '-swift-version', '5', '-target', target,
                    '-whole-module-optimization', '-D', 'CALENDAR_CHECKS', '-I', str(root), '-F', str(frameworks), '-framework', 'Sparkle',
                    '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', str(root / 'CalendarCore.o'),
                    *map(str, sorted((ROOT / 'Sources/PerpetualCalendar').glob('*.swift'))),
                    str(ROOT / 'Tests/InteractionChecks.swift'), str(ROOT / 'Tests/MonthPagingChecks.swift'),
                    '-o', str(macos / 'Checks')], check=True, env=env)
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='org.menubar-calendar.interface-checks.' + uuid.uuid4().hex,
                CFBundleExecutable='Checks', SUEnableAutomaticChecks=False)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['xcrun', 'strip', '-x', str(macos / 'Checks')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    # Launch as a GUI app so macOS grants the same activation/focus behavior as a normal launch.
    # `open -W` doesn't propagate the application's exit status, so require an explicit success file.
    result = root / 'checks-passed'
    output = root / 'checks-stdout.log'
    errors = root / 'checks-stderr.log'
    command = ['open', '-n', '-W', '--stdout', str(output), '--stderr', str(errors)]
    if 'CALENDAR_NOTE_TEST_OUTPUT' in env:
        command += ['--env', 'CALENDAR_NOTE_TEST_OUTPUT=' + env['CALENDAR_NOTE_TEST_OUTPUT']]
    command += [str(app), '--args', *sys.argv[1:], '--result-file', str(result)]
    try:
        subprocess.run(command, check=True, env=env, timeout=30)
    finally:
        if output.exists():
            sys.stdout.write(output.read_text())
        if errors.exists():
            sys.stderr.write(errors.read_text())
    if not result.exists() or result.read_text() != 'passed':
        raise RuntimeError('Native interface checks failed; see the assertion above.')
