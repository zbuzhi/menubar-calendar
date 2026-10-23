"""Fail-closed checks shared by release upload and its offline checks."""
import base64
import hashlib
import json
import os
import pathlib
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'

def verify_signature(path, key, signature=None):
    source = ROOT/'scripts/VerifyUpdateSignature.swift'
    verifier = ROOT/'.build'/('verify-update-'+hashlib.sha256(source.read_bytes()).hexdigest()[:16])
    if not verifier.exists():
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT/'.build/clang-cache'))
        subprocess.run(['swiftc', str(source), '-o', str(verifier)], env=env, check=True)
    command = [str(verifier), key, str(path)]
    if signature is not None:
        command.append(signature)
    subprocess.run(command, check=True)

def load_release(directory):
    meta = json.loads((directory/'release.json').read_text())
    version = meta['version']
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('版本格式异常')
    name = meta['archive']
    # Previously signed local releases retain their original archive names.
    if name not in (f'menubar-calendar-{version}-universal.zip', f'PerpetualCalendar-{version}-universal.zip'):
        raise ValueError('安装包名称异常')
    if (meta['repository'] not in ('zbuzhi/menubar-calendar', 'zbuzhi/calendar-holidays') or meta['tag'] != f'app-v{version}'
        or type(meta['build']) is not int or meta['build'] <= 0):
        raise ValueError('发布元数据异常')
    archive, feed = directory/name, directory/'appcast.xml'
    if (hashlib.sha256(archive.read_bytes()).hexdigest() != meta['sha256']
        or hashlib.sha256(feed.read_bytes()).hexdigest() != meta['appcastSHA256']):
        raise ValueError('打包后内容已变化，请重新生成签名更新')
    item = ET.fromstring(feed.read_bytes()).find('./channel/item')
    enclosure = item.find('enclosure')
    expected = f'https://github.com/{meta["repository"]}/releases/download/{meta["tag"]}/{name}'
    if (item.findtext(NS+'version') != str(meta['build'])
        or item.findtext(NS+'shortVersionString') != version
        or enclosure.get('url') != expected
        or enclosure.get('length') != str(archive.stat().st_size)):
        raise ValueError('清单与安装包元数据不一致')
    key = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())['SUPublicEDKey']
    if key != meta['publicKey'] or len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError('发布公钥与应用配置不同')
    verify_signature(archive, key, enclosure.get(NS+'edSignature'))
    verify_signature(feed, key)
    return meta, archive, feed
