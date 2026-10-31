# SPDX-License-Identifier: Apache-2.0
"""Check notarization recovery and release gates without contacting Apple."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class NotarizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['scripts', 'dist', 'bin']:
            (self.root / folder).mkdir()
        (self.root / 'VERSION').write_text('1.3.3\n')
        self.pkg = self.root / 'dist/ChemDraw-Add-in-for-Mac-1.3.3-universal.pkg'
        self.pkg.write_bytes(b'signed installer')
        self.log = self.root / 'calls.jsonl'
        shim = self.root / 'bin/shim'
        shim.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ['NOTARY_LOG'], 'a') as log: log.write(json.dumps([name] + args) + '\\n')
if name == 'pkgutil':
    if os.environ.get('BAD_SIGNATURE') == '1': sys.exit(1)
    print('1. Developer ID Installer: Test (ABC1234567)')
elif name == 'spctl': sys.exit(int(os.environ.get('GATEKEEPER_RESULT', '0')))
elif name == 'codesign': sys.exit(int(os.environ.get('BAD_SIGNATURE', '0')))
elif name == 'zsh':
    if os.environ.get('UPDATE_TICKET_RESULT') == '1': sys.exit(1)
    archive = pathlib.Path(args[-1]); archive.write_bytes(archive.read_bytes() + b' app ticket')
elif args[:2] == ['stapler', 'validate']:
    sys.exit(0 if pathlib.Path(args[-1]).read_bytes().endswith(b' ticket') else 1)
elif args[:2] == ['stapler', 'staple']:
    pkg = pathlib.Path(args[-1]); pkg.write_bytes(pkg.read_bytes() + b' ticket')
elif args[:2] == ['notarytool', 'history']:
    sys.exit(int(os.environ.get('CREDENTIAL_RESULT', '0')))
elif args[:2] == ['notarytool', 'submit']:
    print(json.dumps({'id': 'submission-123'}))
    sys.exit(int(os.environ.get('SUBMIT_RESULT', '0')))
elif args[:2] == ['notarytool', 'wait']:
    if os.environ.get('REBUILD_DURING_WAIT') == '1': pathlib.Path(os.environ['NOTARY_PACKAGE']).write_bytes(b'newer installer')
    print(json.dumps({'id': args[2], 'status': os.environ.get('NOTARY_STATUS', 'Accepted')}))
    sys.exit(int(os.environ.get('WAIT_RESULT', '0')))
elif args[:2] == ['notarytool', 'info']:
    print(json.dumps({'id': args[2], 'status': os.environ.get('NOTARY_STATUS', 'Accepted')}))
elif args[:2] == ['notarytool', 'log']:
    pathlib.Path(args[-1]).write_text(json.dumps({'status': os.environ.get('NOTARY_STATUS', 'Accepted')}))
''')
        shim.chmod(0o755)
        for name in ['xcrun', 'pkgutil', 'spctl', 'codesign', 'zsh']:
            (self.root / 'bin' / name).symlink_to(shim)
        source = (PROJECT / 'scripts/notarize.sh').read_text()
        for name in ['pkgutil', 'spctl']:
            source = source.replace('/usr/sbin/' + name, str(self.root / 'bin' / name))
        source = source.replace('/usr/bin/codesign', str(self.root / 'bin/codesign'))
        self.script = self.root / 'scripts/notarize.sh'
        self.script.write_text(source)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('CFM_')}
        self.env.update(PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'], NOTARY_LOG=str(self.log), NOTARY_PACKAGE=str(self.pkg))

    def run_notary(self, *args):
        return subprocess.run(['/bin/zsh', str(self.script), *args], env=self.env, text=True, capture_output=True)

    def calls(self, prefix):
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [c for c in calls if c[:len(prefix)] == prefix]

    def test_accepted_ticket_is_attached_before_final_integrity_asset(self):
        result = self.run_notary()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.pkg.read_bytes().endswith(b' ticket'))
        self.assertIn(hashlib.sha256(self.pkg.read_bytes()).hexdigest(), (self.root / 'dist/SHA256SUMS.txt').read_text())
        self.assertEqual(len(self.calls(['spctl'])), 1)
        self.assertIn('ChemDraw Add-in', self.calls(['xcrun', 'notarytool', 'submit'])[0])

    def test_timeout_resumes_same_submission_without_reupload(self):
        self.env.update(NOTARY_STATUS='In Progress', WAIT_RESULT='1')
        result = self.run_notary()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('submission-123', result.stderr)
        self.assertFalse(self.calls(['xcrun', 'stapler', 'staple']))
        self.env.update(NOTARY_STATUS='Accepted', WAIT_RESULT='0')
        self.assertEqual(self.run_notary().returncode, 0)
        self.assertEqual(len(self.calls(['xcrun', 'notarytool', 'submit'])), 1)

    def test_changed_installer_gets_its_own_submission(self):
        self.env.update(NOTARY_STATUS='In Progress', WAIT_RESULT='1')
        self.run_notary()
        self.pkg.write_bytes(b'new signed installer')
        self.run_notary()
        self.assertEqual(len(self.calls(['xcrun', 'notarytool', 'submit'])), 2)

    def test_rebuild_during_wait_preserves_newer_installer(self):
        self.env['REBUILD_DURING_WAIT'] = '1'
        result = self.run_notary()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('changed while Apple was processing', result.stderr)
        self.assertEqual(self.pkg.read_bytes(), b'newer installer')
        snapshots = [p for p in (self.root / 'build/notarization').rglob('*.pkg') if p.is_file()]
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0].read_bytes(), b'signed installer ticket')

    def test_rejection_keeps_log_and_never_attaches_ticket(self):
        self.env.update(NOTARY_STATUS='Invalid', WAIT_RESULT='1')
        result = self.run_notary()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('log.json', result.stderr)
        self.assertEqual(len(list((self.root / 'build').rglob('log.json'))), 1)
        self.assertFalse(self.calls(['xcrun', 'stapler', 'staple']))
        self.assertFalse((self.root / 'dist/SHA256SUMS.txt').exists())

    def test_completed_package_is_not_uploaded_again(self):
        self.assertEqual(self.run_notary().returncode, 0)
        self.assertEqual(self.run_notary().returncode, 0)
        self.assertEqual(len(self.calls(['xcrun', 'notarytool', 'submit'])), 1)

    def test_failed_signature_and_failed_submission_stop(self):
        self.env['BAD_SIGNATURE'] = '1'
        self.assertNotEqual(self.run_notary().returncode, 0)
        self.assertFalse(self.calls(['xcrun', 'notarytool', 'submit']))
        self.env.pop('BAD_SIGNATURE')
        self.env['SUBMIT_RESULT'] = '1'
        self.assertNotEqual(self.run_notary().returncode, 0)
        self.assertFalse(self.calls(['xcrun', 'notarytool', 'wait']))

    def test_failed_gatekeeper_does_not_emit_final_integrity_asset(self):
        self.env['GATEKEEPER_RESULT'] = '1'
        self.assertNotEqual(self.run_notary().returncode, 0)
        self.assertFalse((self.root / 'dist/SHA256SUMS.txt').exists())

    def test_credential_preflight_uses_profile_without_uploading(self):
        self.env.update(CFM_NOTARY_PROFILE='another-profile', CREDENTIAL_RESULT='1')
        self.assertNotEqual(self.run_notary('--check-credentials').returncode, 0)
        self.assertIn('another-profile', self.calls(['xcrun', 'notarytool', 'history'])[0])
        self.assertFalse(self.calls(['xcrun', 'notarytool', 'submit']))

    def test_dmg_and_update_app_tickets_precede_final_distribution_metadata(self):
        dmg = self.pkg.with_suffix('.dmg'); dmg.write_bytes(b'signed disk image')
        archive = self.pkg.with_suffix('.zip'); archive.write_bytes(b'signed app archive')
        result = self.run_notary()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(dmg.read_bytes().endswith(b' ticket'))
        self.assertTrue(archive.read_bytes().endswith(b' app ticket'))
        metadata = (self.root / 'dist/SHA256SUMS.txt').read_text()
        self.assertIn(hashlib.sha256(dmg.read_bytes()).hexdigest(), metadata)
        self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), metadata)

    def test_failed_update_app_ticket_stops_final_distribution_metadata(self):
        self.pkg.with_suffix('.dmg').write_bytes(b'signed disk image')
        self.pkg.with_suffix('.zip').write_bytes(b'signed app archive')
        self.env['UPDATE_TICKET_RESULT'] = '1'
        self.assertNotEqual(self.run_notary().returncode, 0)
        self.assertFalse((self.root / 'dist/SHA256SUMS.txt').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
