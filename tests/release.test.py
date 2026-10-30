# SPDX-License-Identifier: Apache-2.0
"""Run release orchestration against local command shims; never publish."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['scripts', 'packaging', 'bin', 'build']:
            (self.root / folder).mkdir()
        (self.root / 'VERSION').write_text('1.3.3\n')
        self.log = self.root / 'commands.jsonl'
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('CFM_')}
        self.env.update(PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'], RELEASE_LOG=str(self.log))
        shim = self.root / 'bin/shim'
        shim.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['RELEASE_LOG'], 'a') as log: log.write(json.dumps([name] + args) + '\\n')
if name == 'security':
    kind = 'Application' if args[-1] == 'codesigning' else 'Installer'
    available = os.environ.get('SIGN_AVAILABLE' if kind == 'Application' else 'INSTALLER_AVAILABLE', '1')
    print('  1) ' + 'A' * 40 + ' "Developer ID ' + kind + ': Test (ABC1234567)"' if available == '1' else '0 valid identities found')
elif name == 'git':
    if args[:1] == ['branch']: print('main')
    elif args[:2] == ['remote', 'get-url']: print('https://github.com/BoeingART/chemdraw-add-in-for-mac.git')
    elif args[:1] == ['ls-files']: print(os.environ.get('UNRELATED_FILE', ''))
    elif args == ['diff', '--cached', '--quiet']: sys.exit(1)
    elif args[:2] == ['rev-parse', '--verify']: sys.exit(1)
elif name == 'gh':
    if args[:1] == ['api']:
        if os.environ.get('NETWORK_FAILURE') == '1': sys.exit(1)
        print('true')
    elif args[:2] == ['release', 'view']:
        if '--json' in args: print('{}')
        else: sys.exit(0 if os.environ.get('EXISTING_RELEASE') == '1' else 1)
elif name == 'zsh':
    if args == ['scripts/notarize.sh', '--check-credentials'] and os.environ.get('CREDENTIAL_FAILURE') == '1': sys.exit(1)
    if len(args) == 1 and args[0] == os.environ.get('FAIL_STEP'): sys.exit(1)
    if args == ['scripts/test-package.sh'] and os.environ.get('CFM_REQUIRE_NOTARIZATION') == '1' and os.environ.get('FINAL_VALIDATION_FAILURE') == '1': sys.exit(1)
    if args[0] == 'scripts/package.sh':
        pathlib.Path('dist').mkdir(exist_ok=True)
        pathlib.Path('dist/ChemDraw-Add-in-for-Mac-1.3.3-universal.pkg').write_bytes(b'fixture')
        pathlib.Path('dist/SHA256SUMS.txt').write_text('fixture')
''')
        shim.chmod(0o755)
        for name in ['git', 'gh', 'security', 'zsh', 'node']:
            (self.root / 'bin' / name).symlink_to(shim)
        (self.root / 'tests').mkdir()
        (self.root / 'tests/installer.test.py').write_text('')
        (self.root / 'tests/release.test.py').write_text('')
        (self.root / 'tests/signing.test.py').write_text('')
        (self.root / 'tests/notarization.test.py').write_text('')
        signing = (PROJECT / 'scripts/signing.sh').read_text().replace('/usr/bin/security', str(self.root / 'bin/security'))
        (self.root / 'scripts/signing.sh').write_text(signing)
        source = (PROJECT / 'scripts/release-1.3.3.sh').read_text()
        self.script = self.root / 'scripts/release-1.3.3.sh'
        self.script.write_text(source)

    def run_release(self):
        return subprocess.run(['/bin/zsh', str(self.script)], env=self.env, text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def mutations(self):
        return [c for c in self.commands() if c[:2] in [['git', 'add'], ['git', 'commit'], ['git', 'tag'], ['git', 'push']] or c[:3] == ['gh', 'release', 'create']]

    def test_missing_developer_id_stops_before_build_or_publication(self):
        self.env['SIGN_AVAILABLE'] = '0'
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Developer ID Application identity; found 0', result.stderr)
        self.assertFalse(self.mutations())
        self.assertFalse(any(c[0] in ['gh', 'zsh'] for c in self.commands()))

    def test_network_failure_stops_before_build_or_mutation(self):
        self.env['NETWORK_FAILURE'] = '1'
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.mutations())
        self.assertEqual([c for c in self.commands() if c[0] == 'zsh'], [['zsh', 'scripts/notarize.sh', '--check-credentials']])

    def test_missing_installer_stops_before_build_or_publication(self):
        self.env['INSTALLER_AVAILABLE'] = '0'
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.mutations())
        self.assertFalse(any(c[0] in ['gh', 'zsh'] for c in self.commands()))

    def test_missing_notary_credentials_stop_before_build(self):
        self.env['CREDENTIAL_FAILURE'] = '1'
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.mutations())
        self.assertEqual([c for c in self.commands() if c[0] == 'zsh'], [['zsh', 'scripts/notarize.sh', '--check-credentials']])

    def test_unrelated_changes_are_not_committed(self):
        self.env['UNRELATED_FILE'] = 'unrelated-user-notes.txt'
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unrelated-user-notes.txt', result.stderr)
        self.assertFalse(self.mutations())

    def test_failed_package_validation_cannot_push_or_publish(self):
        self.env['FAIL_STEP'] = 'scripts/test-package.sh'
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.mutations())

    def test_failed_notarization_cannot_push_or_publish(self):
        self.env['FAIL_STEP'] = 'scripts/notarize.sh'
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.mutations())
        self.assertIn(['zsh', 'scripts/package.sh'], self.commands())

    def test_failed_final_notarization_validation_cannot_publish(self):
        self.env['FINAL_VALIDATION_FAILURE'] = '1'
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.mutations())
        self.assertIn(['zsh', 'scripts/notarize.sh'], self.commands())

    def test_existing_release_is_preserved(self):
        self.env['EXISTING_RELEASE'] = '1'
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.mutations())
        self.assertEqual([c for c in self.commands() if c[0] == 'zsh'], [['zsh', 'scripts/notarize.sh', '--check-credentials']])

    def test_release_uses_verified_assets_and_exact_tag_after_checks(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.commands()
        verification = max(i for i, c in enumerate(calls) if c == ['zsh', 'scripts/test-package.sh'])
        notarization = calls.index(['zsh', 'scripts/notarize.sh'])
        push = next(i for i, c in enumerate(calls) if c[:2] == ['git', 'push'])
        release = next(i for i, c in enumerate(calls) if c[:3] == ['gh', 'release', 'create'])
        self.assertLess(verification, push)
        self.assertLess(notarization, verification)
        self.assertLess(push, release)
        self.assertEqual(calls[push], ['git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/main', 'refs/tags/v1.3.3'])
        args = calls[release]
        self.assertEqual(args[3:6], ['v1.3.3', 'dist/ChemDraw-Add-in-for-Mac-1.3.3-universal.pkg', 'dist/SHA256SUMS.txt'])
        self.assertIn('--verify-tag', args)
        self.assertEqual(args[args.index('--notes-file') + 1], 'packaging/ReleaseNotes.md')
        added = next(c for c in calls if c[:2] == ['git', 'add'])
        self.assertNotIn('-A', added)
        self.assertNotIn('dist/SHA256SUMS.txt', added)


if __name__ == '__main__':
    unittest.main(verbosity=2)
