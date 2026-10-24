#!/usr/bin/env python3
"""Compile Apple's layered icon, or package the matching static fallback with CLT-only setups."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Resources/AppIcon.icon'
CACHE = ROOT / '.build/brand-icon'

def build(app, static_only=False):
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    native = False
    compiler = subprocess.run(['xcrun', '--find', 'actool'], capture_output=True, text=True)
    sdk = subprocess.run(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], capture_output=True, text=True)
    supports_layers = sdk.returncode == 0 and sdk.stdout.strip().split('.')[0].isdigit() and int(sdk.stdout.strip().split('.')[0]) >= 26
    if not static_only and compiler.returncode == 0 and supports_layers:
        tool = Path(compiler.stdout.strip())
        digest = hashlib.sha256()
        for path in sorted(SOURCE.rglob('*')):
            if path.is_file() and not path.name.startswith('.'):
                digest.update(str(path.relative_to(SOURCE)).encode()); digest.update(path.read_bytes())
        digest.update(f'{tool}:{tool.stat().st_mtime_ns}:{sdk.stdout.strip()}:macosx:13.0:v1'.encode())
        expected = {'fingerprint': digest.hexdigest()}
        stamp = CACHE / 'cache.json'
        cached = json.loads(stamp.read_text()) if stamp.exists() else None
        outputs = ['Assets.car', 'AppIcon.icns', 'partial.plist']
        if cached != expected or not all((CACHE / name).is_file() for name in outputs):
            CACHE.mkdir(parents=True, exist_ok=True)
            subprocess.run([str(tool), str(SOURCE), '--compile', str(CACHE), '--platform', 'macosx',
                            '--minimum-deployment-target', '13.0', '--app-icon', 'AppIcon', '--include-all-app-icons',
                            '--output-partial-info-plist', str(CACHE / 'partial.plist'),
                            '--output-format', 'human-readable-text', '--notices', '--warnings', '--errors'], check=True)
            stamp.write_text(json.dumps(expected) + '\n')
        shutil.copy2(CACHE / 'Assets.car', resources / 'Assets.car')
        shutil.copy2(CACHE / 'AppIcon.icns', resources / 'AppIcon.icns')
        partial = plistlib.loads((CACHE / 'partial.plist').read_bytes())
        for key in ('CFBundleIconName', 'CFBundleIconFile', 'CFBundleIcons'):
            if key in partial:
                info[key] = partial[key]
        native = True
    else:
        generated = ROOT / '.build/static-icon'
        generated.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / '.build/clang-cache'))
        subprocess.run(['swift', str(ROOT / 'scripts/make-icon.swift'), str(generated / 'AppIcon.iconset'),
                        str(generated / 'AppIcon.icns'), str(ROOT / 'Resources/Branding/AppIcon.png')],
                       cwd=ROOT, env=env, check=True)
        shutil.copy2(generated / 'AppIcon.icns', resources / 'AppIcon.icns')
        (resources / 'Assets.car').unlink(missing_ok=True)
        info.pop('CFBundleIconName', None)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info, sort_keys=False))
    print('图标：原生浅色／深色／染色 + 系统兼容图标' if native else '图标：静态兼容版本（兼容旧工具链）')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--static-only', action='store_true')
    args = parser.parse_args()
    build(args.app.resolve(), args.static_only)
