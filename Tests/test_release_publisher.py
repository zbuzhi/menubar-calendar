"""Publishing safety checks without GitHub credentials or network writes."""
import base64
import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
spec = importlib.util.spec_from_file_location('publisher', ROOT/'scripts/publish-release.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

class PublisherChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = pathlib.Path(self.tmp.name)
        self.archive = self.directory/'menubar-calendar-0.1.6-universal.zip'
        self.archive.write_bytes(b'test signed archive')
        self.feed = self.directory/'appcast.xml'
        self.feed.write_bytes(b'test signed feed')
        self.meta = dict(repository='zbuzhi/calendar-holidays', tag='app-v0.1.6', version='0.1.6',
                         build=7, sha256=hashlib.sha256(self.archive.read_bytes()).hexdigest())
        self.calls = []
        self.private = False
        self.bad_download = False
        self.concurrent = False
        self.old_feed = b'<rss><channel/></rss>'

    def fake_gh(self, *args, input_text=None, check=True):
        self.calls.append((args, input_text))
        if args[:2] == ('api', 'repos/zbuzhi/calendar-holidays'):
            output = 'true' if self.private else 'false'
        elif args[0] == 'api' and '--method' not in args:
            output = json.dumps({'sha': 'expected-old-sha', 'content': base64.b64encode(self.old_feed).decode()})
        elif args[:2] == ('release', 'view'):
            return subprocess.CompletedProcess(args, 1, '', 'not found')
        elif args[:2] == ('release', 'download'):
            folder = pathlib.Path(args[args.index('--dir')+1])
            (folder/self.archive.name).write_bytes(b'changed' if self.bad_download else self.archive.read_bytes())
            output = ''
        elif args[0] == 'api' and '--method' in args:
            payload = json.loads(input_text)
            self.assertEqual(payload['sha'], 'expected-old-sha')
            self.assertEqual(base64.b64decode(payload['content']), self.feed.read_bytes())
            return subprocess.CompletedProcess(args, 1 if self.concurrent else 0, '', 'conflict' if self.concurrent else '')
        else:
            output = ''
        return subprocess.CompletedProcess(args, 0, output, '')

    def run_publish(self, public):
        with patch.object(publisher.shutil, 'which', return_value='/test/gh'), \
             patch.object(publisher, 'load_release', return_value=(self.meta, self.archive, self.feed)), \
             patch.object(publisher, 'gh', side_effect=self.fake_gh):
            publisher.publish(self.directory, public)

    def test_default_upload_is_draft_and_does_not_change_feed(self):
        self.run_publish(False)
        self.assertTrue(any(args[:2] == ('release', 'create') and '--draft' in args for args, _ in self.calls))
        self.assertFalse(any(args[:2] == ('release', 'edit') or '--method' in args for args, _ in self.calls))

    def test_publish_downloads_and_verifies_before_release_then_feed(self):
        self.run_publish(True)
        download = next(i for i, (a, _) in enumerate(self.calls) if a[:2] == ('release', 'download'))
        public = next(i for i, (a, _) in enumerate(self.calls) if a[:2] == ('release', 'edit'))
        feed = next(i for i, (a, _) in enumerate(self.calls) if '--method' in a)
        self.assertLess(download, public)
        self.assertLess(public, feed)

    def test_changed_remote_archive_prevents_publication(self):
        self.bad_download = True
        with self.assertRaises(SystemExit): self.run_publish(True)
        self.assertFalse(any(a[:2] == ('release', 'edit') or '--method' in a for a, _ in self.calls))

    def test_private_repository_is_refused(self):
        self.private = True
        with self.assertRaises(SystemExit): self.run_publish(True)
        self.assertEqual(len(self.calls), 1)

    def test_newer_remote_build_is_never_overwritten(self):
        self.old_feed = b'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>8</sparkle:version></item></channel></rss>'
        with self.assertRaises(SystemExit): self.run_publish(True)
        self.assertFalse(any(a[0] == 'release' for a, _ in self.calls))

    def test_concurrent_feed_update_reports_failure_without_forcing(self):
        self.concurrent = True
        with self.assertRaisesRegex(SystemExit, '清单未更新'): self.run_publish(True)
        self.assertEqual(sum('--method' in a for a, _ in self.calls), 1)

if __name__ == '__main__':
    unittest.main()
