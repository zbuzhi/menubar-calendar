#!/usr/bin/env python3
"""Initialize a per-app Sparkle signing key in Keychain; write only its public key."""
import pathlib
import plistlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
ACCOUNT = 'com.perpetualcalendar.mac'

def main():
    tool = TOOLS / 'generate_keys'
    if not tool.is_file():
        raise SystemExit('请先运行 scripts/build-app.sh 下载 Sparkle。')
    path = ROOT / 'Resources/Info.plist'
    info = plistlib.loads(path.read_bytes())
    if not info.get('SUPublicEDKey'):
        subprocess.run([str(tool), '--account', ACCOUNT], check=True)
    key = subprocess.check_output([str(tool), '--account', ACCOUNT, '-p'], text=True).strip()
    import base64
    if len(base64.b64decode(key, validate=True)) != 32:
        raise SystemExit('Sparkle 公钥格式异常；未修改配置。')
    if info.get('SUPublicEDKey', key) != key:
        raise SystemExit('钥匙串公钥与应用配置不同，拒绝替换；请恢复原签名钥匙串。')
    info['SUPublicEDKey'] = key
    path.write_bytes(plistlib.dumps(info, sort_keys=False))
    print('Sparkle 公钥已写入 Info.plist；私钥仅保留在本机钥匙串。')

if __name__ == '__main__':
    main()
