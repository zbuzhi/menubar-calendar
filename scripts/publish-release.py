#!/usr/bin/env python3
"""Upload a reviewed local release with GitHub CLI; publish its feed only after assets exist.

Default creates a draft. --publish makes the release and signed appcast public.
No CI runner, server, or signing private key upload is involved.
"""
import argparse
import base64
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from prepare_release_support import load_release

def gh(*args, input_text=None, check=True):
    return subprocess.run(['gh', *args], input=input_text, text=True, capture_output=True, check=check)

def publish(directory, make_public):
    if not shutil.which('gh'):
        raise SystemExit('请安装 GitHub 官方 CLI 并运行 gh auth login；也可按 docs/RELEASING.md 从网页上传。')
    meta, archive, feed = load_release(directory)
    repo, tag = meta['repository'], meta['tag']
    feed_repo = 'zbuzhi/calendar-holidays'
    if gh('api', f'repos/{repo}', '--jq', '.private').stdout.strip() != 'false':
        raise SystemExit('只允许发布到既定公开仓库，避免私有存储或计费变化。')
    # Capture the old blob SHA before publication: a concurrent update must not be overwritten.
    old = json.loads(gh('api', f'repos/{feed_repo}/contents/updates/appcast.xml?ref=main').stdout)
    old_xml = base64.b64decode(old['content'])
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    versions = [int(x.text) for x in ET.fromstring(old_xml).findall(f'./channel/item/{ns}version')]
    if versions and max(versions) >= meta['build']:
        if old_xml == feed.read_bytes():
            print('同一更新清单已发布，无需重复上传。')
            return
        raise SystemExit('新构建号必须大于已发布构建号；拒绝回退或覆盖其他版本。')
    existing = gh('release', 'view', tag, '--repo', repo, '--json', 'isDraft', check=False)
    if existing.returncode != 0:
        gh('release', 'create', tag, str(archive), '--repo', repo, '--target', 'main', '--draft',
           '--title', f'不知时日历 {meta["version"]}', '--notes-file', str(directory/'release-notes.md'))
    # Validate the actual download, including when resuming a previous upload.
    with tempfile.TemporaryDirectory(prefix='calendar-release-') as folder:
        gh('release', 'download', tag, '--repo', repo, '--pattern', archive.name, '--dir', folder)
        downloaded = pathlib.Path(folder)/archive.name
        if hashlib.sha256(downloaded.read_bytes()).hexdigest() != meta['sha256']:
            raise SystemExit('GitHub 安装包与本机签名包不一致，拒绝发布更新清单。')
    if not make_public:
        print(f'草稿安装包已上传并核对；尚未推送给用户：https://github.com/{repo}/releases')
        return
    gh('release', 'edit', tag, '--repo', repo, '--draft=false', '--latest')
    payload = {'message': f'发布 {meta["version"]}', 'branch': 'main',
               'sha': old['sha'], 'content': base64.b64encode(feed.read_bytes()).decode('ascii')}
    result = gh('api', f'repos/{feed_repo}/contents/updates/appcast.xml', '--method', 'PUT', '--input', '-',
                input_text=json.dumps(payload), check=False)
    if result.returncode:
        raise SystemExit('安装包已公开，但清单未更新（可能有并发提交）。旧版仍可用；核对后重新执行发布命令。\n'+result.stderr)
    print(f'已发布签名更新：https://github.com/{repo}/releases/tag/{tag}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=pathlib.Path)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    publish(args.directory.resolve(), args.publish)
