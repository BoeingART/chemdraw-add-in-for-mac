# SPDX-License-Identifier: Apache-2.0
"""Exercise Developer ID selection without modifying the real keychain."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
TEAM = 'ABC1234567'
OTHER_TEAM = 'DEF1234567'


def identity(number, kind, team=TEAM):
    return f'  1) {str(number) * 40} "Developer ID {kind}: Test ({team})"\n'


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        security = self.root / 'security'
        security.write_text('''#!/usr/bin/env python3
import os, sys
print(os.environ['APP_IDENTITIES' if sys.argv[-1] == 'codesigning' else 'INSTALLER_IDENTITIES'])
''')
        security.chmod(0o755)
        source = (PROJECT / 'scripts/signing.sh').read_text().replace('/usr/bin/security', str(security))
        self.script = self.root / 'signing.sh'
        self.script.write_text(source)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('CFM_')}
        self.env.update(APP_IDENTITIES=identity(1, 'Application'), INSTALLER_IDENTITIES=identity(2, 'Installer'))

    def resolve(self):
        return subprocess.run(['/bin/zsh', '-c', 'set -euo pipefail; source "$1"; cfm_resolve_distribution_signing; print -r -- "$CFM_TEAM_ID|$CFM_APP_SIGNING_ID|$CFM_INSTALLER_SIGNING_NAME"', 'test', str(self.script)], env=self.env, text=True, capture_output=True)

    def test_selects_matching_application_and_installer(self):
        result = self.resolve()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'{TEAM}|{"1" * 40}|Developer ID Installer:', result.stdout)

    def test_missing_application_stops(self):
        self.env['APP_IDENTITIES'] = '0 valid identities found'
        result = self.resolve()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Developer ID Application identity; found 0', result.stderr)

    def test_missing_installer_stops(self):
        self.env['INSTALLER_IDENTITIES'] = ''
        self.assertNotEqual(self.resolve().returncode, 0)

    def test_installer_from_other_team_is_rejected(self):
        self.env['INSTALLER_IDENTITIES'] = identity(2, 'Installer', OTHER_TEAM)
        self.assertNotEqual(self.resolve().returncode, 0)

    def test_ambiguous_team_requires_selection(self):
        self.env['APP_IDENTITIES'] += identity(3, 'Application', OTHER_TEAM)
        self.assertNotEqual(self.resolve().returncode, 0)
        self.env['CFM_TEAM_ID'] = TEAM
        self.assertEqual(self.resolve().returncode, 0)

    def test_exact_application_selector_resolves_ambiguity(self):
        self.env['APP_IDENTITIES'] += identity(3, 'Application')
        self.assertNotEqual(self.resolve().returncode, 0)
        self.env['CFM_SIGN_IDENTITY'] = '1' * 40
        self.assertEqual(self.resolve().returncode, 0)

    def test_wrong_certificate_type_and_unknown_selector_stop(self):
        self.env['APP_IDENTITIES'] = identity(1, 'Installer')
        self.assertNotEqual(self.resolve().returncode, 0)
        self.env['APP_IDENTITIES'] = identity(1, 'Application')
        self.env['CFM_SIGN_IDENTITY'] = 'Test'
        self.assertNotEqual(self.resolve().returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
