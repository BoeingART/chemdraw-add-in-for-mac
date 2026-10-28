# SPDX-License-Identifier: Apache-2.0
"""Exercise packaged installer scripts without touching real consent or applications."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apps = self.root / 'Applications'
        self.apps.mkdir()
        self.log = self.root / 'calls.txt'
        self.env = dict(os.environ, TEST_LOG=str(self.log), TEST_USER='desktop-user')
        self.info = plistlib.loads((PROJECT / 'packaging/Info.plist').read_bytes())
        self.write_info()
        shim = self.root / 'shim'
        shim.write_text('''#!/usr/bin/env python3
import os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['TEST_LOG'], 'a') as log:
    log.write(name + '|' + '|'.join(args) + '\\n')
if name == 'stat': print(os.environ['TEST_USER'])
elif name == 'id': print('501')
elif name in ('launchctl', 'sudo'): sys.exit(subprocess.run(args[2:]).returncode)
elif name == 'tccutil':
    print(os.environ.get('TEST_RESET_MESSAGE', 'Successfully reset file access'))
    sys.exit(int(os.environ.get('TEST_RESET_STATUS', '0')))
elif name == 'open': sys.exit(int(os.environ.get('TEST_OPEN_STATUS', '0')))
elif name == 'rm':
    for target in args:
        if not target.startswith('-'): __import__('shutil').rmtree(target)
''')
        shim.chmod(0o755)
        commands = ['/usr/bin/stat', '/usr/bin/id', '/bin/launchctl', '/usr/bin/sudo', '/usr/bin/tccutil', '/usr/bin/open', '/bin/rm']
        for command in commands:
            (self.root / Path(command).name).symlink_to(shim)
        for name in ['preinstall', 'postinstall']:
            source = (PROJECT / 'packaging/scripts' / name).read_text()
            for command in commands:
                source = source.replace(command, str(self.root / Path(command).name))
            source = source.replace('/Applications/', str(self.apps) + '/')
            (self.root / name).write_text(source)

    def write_info(self):
        (self.root / 'app-info.plist').write_bytes(plistlib.dumps(self.info))

    def run_script(self, name, target='/'):
        return subprocess.run(['/bin/sh', str(self.root / name), 'package', '/', target], env=self.env, text=True, capture_output=True)

    def calls(self, name):
        lines = self.log.read_text().splitlines() if self.log.exists() else []
        return [line.split('|')[1:] for line in lines if line.startswith(name + '|')]

    def app(self, name, bundle):
        app = self.apps / (name + '.app')
        (app / 'Contents').mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle}))
        return app

    def test_fresh_install_renews_only_app_office_access_in_desktop_session(self):
        self.assertEqual(self.run_script('preinstall').returncode, 0)
        self.assertEqual(self.calls('tccutil'), [['reset', 'SystemPolicyAppDataDetailed', self.info['CFBundleIdentifier']]])
        self.assertEqual(self.calls('launchctl')[0][:2], ['asuser', '501'])
        self.assertEqual(self.calls('sudo')[0][:2], ['-u', 'desktop-user'])

    def test_upgrade_renews_office_access_and_preserves_other_services(self):
        self.app('ChemOffice', self.info['CFBundleIdentifier'])
        self.assertEqual(self.run_script('preinstall').returncode, 0)
        self.assertEqual(self.calls('tccutil'), [['reset', 'SystemPolicyAppDataDetailed', self.info['CFBundleIdentifier']]])

    def test_bundle_identity_is_read_from_payload_metadata(self):
        self.info['CFBundleIdentifier'] = 'com.example.renamed-addins'
        self.info['CFBundleDisplayName'] = 'Renamed Add-in'
        self.write_info()
        new = self.app(self.info['CFBundleDisplayName'], self.info['CFBundleIdentifier'])
        self.assertEqual(self.run_script('preinstall').returncode, 0)
        self.assertEqual(self.calls('tccutil'), [['reset', 'SystemPolicyAppDataDetailed', self.info['CFBundleIdentifier']]])
        self.assertEqual(self.run_script('postinstall').returncode, 0)
        self.assertEqual(self.calls('open'), [[str(new), '--args', '--setup']])

    def test_unregistered_first_install_can_continue_to_setup(self):
        for message in ['No such bundle identifier', 'kLSApplicationNotFoundErr']:
            self.env.update(TEST_RESET_STATUS='1', TEST_RESET_MESSAGE=message)
            result = self.run_script('preinstall')
            self.assertEqual(result.returncode, 0)
            self.assertIn('first installation', result.stdout)

    def test_failed_office_access_reset_reports_reason_and_stops_installation(self):
        self.env.update(TEST_RESET_STATUS='1', TEST_RESET_MESSAGE='Failed to reset: permission denied')
        result = self.run_script('preinstall')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('could not renew Office file access', result.stderr)
        self.assertIn('permission denied', result.stderr)
        self.assertFalse(self.calls('open'))

    def test_preinstall_keeps_manifests_and_user_settings(self):
        manifest = self.root / 'Office/wef/chemoffice-for-mac.xml'
        manifest.parent.mkdir(parents=True)
        manifest.write_bytes(b'previous registration')
        settings = self.root / 'preferences.json'
        settings.write_bytes(b'{"authorized":true}')
        result = self.run_script('preinstall')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(manifest.read_bytes(), b'previous registration')
        self.assertEqual(settings.read_bytes(), b'{"authorized":true}')
        self.assertEqual(self.calls('tccutil'), [['reset', 'SystemPolicyAppDataDetailed', self.info['CFBundleIdentifier']]])
        self.assertFalse(self.calls('open'))

    def test_offline_target_touches_neither_permissions_nor_applications(self):
        for name in ['preinstall', 'postinstall']:
            self.assertEqual(self.run_script(name, str(self.root / 'offline')).returncode, 0)
        self.assertFalse(self.log.exists())

    def test_no_desktop_user_never_resets_root_consent_or_launches_setup(self):
        for user in ['root', 'loginwindow', '_mbsetupuser', '']:
            self.env['TEST_USER'] = user
            for name in ['preinstall', 'postinstall']:
                self.assertEqual(self.run_script(name).returncode, 0)
        self.assertFalse(self.calls('tccutil'))
        self.assertFalse(self.calls('open'))

    def test_upgrade_removes_old_bundle_and_opens_new_name_in_user_session(self):
        old = self.app('ChemOffice', self.info['CFBundleIdentifier'])
        new = self.app(self.info['CFBundleDisplayName'], self.info['CFBundleIdentifier'])
        data = self.root / 'Library/Application Support/ChemOffice/work/draft.cdx'
        data.parent.mkdir(parents=True)
        data.write_bytes(b'retained chemistry')
        self.assertEqual(self.run_script('postinstall').returncode, 0)
        self.assertFalse(old.exists())
        self.assertEqual(self.calls('open'), [[str(new), '--args', '--setup']])
        self.assertEqual(data.read_bytes(), b'retained chemistry')

    def test_cleanup_preserves_unrelated_app_and_waits_for_new_payload(self):
        old = self.app('ChemOffice', 'com.example.unrelated')
        self.app(self.info['CFBundleDisplayName'], self.info['CFBundleIdentifier'])
        self.assertEqual(self.run_script('postinstall').returncode, 0)
        self.assertTrue(old.exists())
        shutil.rmtree(self.apps / (self.info['CFBundleDisplayName'] + '.app'))
        (old / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': self.info['CFBundleIdentifier']}))
        self.assertEqual(self.run_script('postinstall').returncode, 0)
        self.assertTrue(old.exists())

    def test_upgrade_removes_all_legacy_display_names_and_retains_new_bundle(self):
        legacy = [self.app(name, self.info['CFBundleIdentifier']) for name in
                  ['ChemOffice', 'ChemOffice Add-ins for Mac', 'ChemOffice Add-in for Mac']]
        new = self.app(self.info['CFBundleDisplayName'], self.info['CFBundleIdentifier'])
        self.assertEqual(self.run_script('postinstall').returncode, 0)
        self.assertTrue(new.exists())
        self.assertTrue(all(not app.exists() for app in legacy))
        self.assertEqual(self.calls('open'), [[str(new), '--args', '--setup']])

    def test_cleanup_preserves_unrelated_app_at_previous_full_name(self):
        old = self.app('ChemOffice Add-ins for Mac', 'com.example.unrelated')
        self.app(self.info['CFBundleDisplayName'], self.info['CFBundleIdentifier'])
        self.assertEqual(self.run_script('postinstall').returncode, 0)
        self.assertTrue(old.exists())

    def test_upgrade_from_original_bundle_identifier(self):
        old = self.app('ChemOffice Add-ins for Mac', 'com.chemoffice.mac')
        new = self.app(self.info['CFBundleDisplayName'], self.info['CFBundleIdentifier'])
        self.assertEqual(self.run_script('postinstall').returncode, 0)
        self.assertFalse(old.exists())
        self.assertTrue(new.exists())
        self.assertEqual(self.calls('open'), [[str(new), '--args', '--setup']])

    def test_setup_launch_failure_is_visible_to_installer(self):
        self.env['TEST_OPEN_STATUS'] = '1'
        self.assertNotEqual(self.run_script('postinstall').returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
