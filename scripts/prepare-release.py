#!/usr/bin/env python3
"""Package locally, sign archive and appcast with Sparkle's Keychain signing tool."""
import argparse
import base64
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
from prepare_release_support import verify_signature

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = 'zbuzhi/menubar-calendar'
ACCOUNT = 'com.perpetualcalendar.mac'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)
FEED = 'https://raw.githubusercontent.com/zbuzhi/calendar-holidays/main/updates/appcast.xml'

def prepare(app, notes):
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.perpetualcalendar.mac' or info.get('SUFeedURL') != FEED:
        raise ValueError('应用标识或更新地址不符')
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('版本号应为 x.y.z，构建号应为递增正整数')
    public_key = info.get('SUPublicEDKey', '')
    if len(base64.b64decode(public_key, validate=True)) != 32:
        raise ValueError('先运行 scripts/setup-updates.py，再重新构建应用')
    tools = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    architectures = subprocess.check_output(['lipo', '-archs', str(app/'Contents/MacOS/PerpetualCalendar')], text=True).split()
    if set(architectures) != {'arm64', 'x86_64'}:
        raise ValueError('公开更新必须同时包含 Intel 和 Apple Silicon 架构')
    output = ROOT / 'dist/releases' / f'app-v{version}'
    output.mkdir(parents=True, exist_ok=False)
    archive = output / f'menubar-calendar-{version}-universal.zip'
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    # One official generator process reads the private key once and signs both files.
    # Public verification below deliberately never re-requests private-key access.
    archive.with_suffix('.txt').write_text(notes, encoding='utf-8')
    feed = output/'appcast.xml'
    subprocess.run([str(tools/'generate_appcast'), '--account', ACCOUNT, '--embed-release-notes',
                    '--maximum-deltas', '0', '--download-url-prefix',
                    f'https://github.com/{REPO}/releases/download/app-v{version}/',
                    '--link', f'https://github.com/{REPO}/releases', str(output)], check=True)
    enclosure = ET.fromstring(feed.read_bytes()).find('./channel/item/enclosure')
    verify_signature(archive, public_key, enclosure.get(f'{{{SPARKLE}}}edSignature'))
    verify_signature(feed, public_key)
    (output/'release-notes.md').write_text(notes, encoding='utf-8')
    metadata = {'repository': REPO, 'tag': f'app-v{version}', 'version': version, 'build': int(build),
                'archive': archive.name, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                'appcastSHA256': hashlib.sha256(feed.read_bytes()).hexdigest(), 'publicKey': public_key}
    (output/'release.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False)+'\n')
    print(f'已生成并验证签名：{output}')
    return output

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=pathlib.Path, default=ROOT/'dist/不知时日历.app')
    parser.add_argument('--notes', type=pathlib.Path, required=True)
    args = parser.parse_args()
    prepare(args.app.resolve(), args.notes.read_text(encoding='utf-8'))
