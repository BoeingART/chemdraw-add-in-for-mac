# SPDX-License-Identifier: Apache-2.0
import sys
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import automation

class ColdLaunchTests(unittest.TestCase):
    def test_failed_native_launch_cannot_send_script_to_an_unready_editor(self):
        with patch.object(automation.subprocess,'run',return_value=CompletedProcess([],2,'','ChemDraw is unavailable')), patch.object(automation,'script') as script:
            with self.assertRaisesRegex(RuntimeError,'unavailable'):
                automation.chem_open(Path('/test/retained-draft.cdx'))
            script.assert_not_called()

    def test_checking_a_closed_editor_does_not_launch_it(self):
        with patch.object(automation.subprocess,'check_output',return_value='no\n'), patch.object(automation,'script') as script:
            self.assertFalse(automation.chem_is_open(Path('/test/retained-draft.cdx')))
            script.assert_not_called()
