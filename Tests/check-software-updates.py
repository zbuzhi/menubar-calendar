#!/usr/bin/env python3
"""Real Sparkle checks against an isolated loopback server; never installs updates."""
import argparse
import http.server
import os
import pathlib
import platform
import plistlib
import shutil
import subprocess
import tempfile
import threading
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main(release, remote_expect):
    app = ROOT/'dist/日历.app'
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT/'.build/clang-cache'))
    env['EXPECTED_BUILD'] = info['CFBundleVersion']
    with tempfile.TemporaryDirectory(prefix='calendar-updater-') as tmp:
        tmp = pathlib.Path(tmp)
        frameworks = tmp/'frameworks'
        frameworks.mkdir()
        subprocess.run(['ditto', str(app/'Contents/Frameworks/Sparkle.framework'), str(frameworks/'Sparkle.framework')], check=True)
        binary = tmp/'probe'
        subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', '-target', platform.machine() + '-apple-macosx13.0',
                        '-F', str(frameworks), '-framework', 'Sparkle', '-Xlinker', '-rpath',
                        '-Xlinker', '@executable_path/../Frameworks', str(ROOT/'Tests/UpdaterChecks.swift'),
                        str(ROOT/'Sources/PerpetualCalendar/SoftwareUpdater.swift'),
                        '-o', str(binary)], check=True, env=env)
        feed_body = (release/'appcast.xml').read_bytes()
        empty_body = (ROOT/'Tests/Fixtures/empty-appcast.xml').read_bytes()
        old = f'<sparkle:version>{info["CFBundleVersion"]}</sparkle:version>'.encode()
        assert old in feed_body
        corrupt_body = feed_body.replace(old, b'<sparkle:version>999999</sparkle:version>', 1)
        class Handler(http.server.BaseHTTPRequestHandler):
            body = b''
            def do_GET(self):
                if self.path != '/appcast.xml':
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header('Content-Type', 'application/rss+xml')
                self.send_header('Content-Length', str(len(self.body)))
                self.end_headers()
                self.wfile.write(self.body)
            def log_message(self, *args):
                pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for case, body in [('available', feed_body), ('current', empty_body), ('tampered', corrupt_body), ('remote', empty_body), ('model', empty_body), ('inline-available', feed_body), ('inline-current', empty_body), ('inline-tampered', corrupt_body)]:
                Handler.body = body
                test_app = tmp/f'{case}.app'
                macos = test_app/'Contents/MacOS'
                macos.mkdir(parents=True)
                shutil.copy2(binary, macos/'Probe')
                subprocess.run(['ditto', str(frameworks), str(test_app/'Contents/Frameworks')], check=True)
                fixture = dict(info, CFBundleIdentifier='com.perpetualcalendar.updaterchecks.'+uuid.uuid4().hex,
                               CFBundleExecutable='Probe', CFBundleName='Updater checks',
                               CFBundleVersion=str(int(info['CFBundleVersion'])-1),
                               CFBundleShortVersionString='0.1.5', SUEnableAutomaticChecks=False,
                               SUFeedURL=f'http://127.0.0.1:{server.server_port}/appcast.xml',
                               NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
                if case == 'remote':
                    fixture['SUFeedURL'] = info['SUFeedURL']
                (test_app/'Contents/Info.plist').write_bytes(plistlib.dumps(fixture))
                subprocess.run(['codesign', '--force', '--sign', '-', str(test_app)], check=True)
                subprocess.run([str(macos/'Probe'), remote_expect if case == 'remote' else case], check=True, timeout=35, env=env)
        finally:
            server.shutdown()
            server.server_close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('release', type=pathlib.Path)
    parser.add_argument('--remote-expect', choices=['available', 'current'], default='available')
    args = parser.parse_args()
    main(args.release.resolve(), args.remote_expect)
