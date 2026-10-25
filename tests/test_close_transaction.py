# SPDX-License-Identifier: Apache-2.0
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import chemoffice
from metadata import encode


class CloseTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.original = b'<CDXML><page><t>before</t></page></CDXML>'
        self.final = b'<CDXML><page><t>last keystroke Z</t></page></CDXML>'
        self.old_tag = encode(self.original)
        self.identity = self.old_tag.split(':')[1]
        self.new_tag = encode(self.final, self.identity)
        self.path = self.root / 'session.cdxml'
        self.path.write_bytes(self.original)
        self.bridge = chemoffice.Bridge()
        self.bridge.session = {'host': 'word', 'document': 'fixture.docx', 'id': self.identity,
                               'path': str(self.path), 'originalTag': self.old_tag, 'busy': False}
        state = patch.object(chemoffice, 'STATE', self.root / 'state.json')
        state.start(); self.addCleanup(state.stop)
        logger = patch.object(chemoffice, 'record')
        logger.start(); self.addCleanup(logger.stop)

    def snapshot(self, path, preview):
        path.write_bytes(self.final)
        Image.new('RGB', (8, 8), 'black').save(preview)

    def test_save_failure_never_closes_or_updates_office(self):
        with patch.object(chemoffice, 'chem_snapshot', side_effect=RuntimeError('save failed')), \
             patch.object(chemoffice, 'chem_close') as close, patch.object(chemoffice, 'office') as office:
            with self.assertRaisesRegex(RuntimeError, 'save failed'): self.bridge.finish('command-w')
            close.assert_not_called(); office.assert_not_called()
        self.assertFalse(self.bridge.session['busy'])

    def test_conflicting_office_edit_is_not_overwritten(self):
        other_tag = encode(b'<CDXML><page><t>another edit</t></page></CDXML>', self.identity)
        with patch.object(chemoffice, 'chem_snapshot', side_effect=self.snapshot), \
             patch.object(chemoffice, 'chem_close') as close, \
             patch.object(chemoffice, 'office', return_value=other_tag) as office:
            with self.assertRaisesRegex(RuntimeError, 'changed during editing'): self.bridge.finish('command-w')
            self.assertEqual([call.args[0] for call in office.call_args_list], ['payload'])
            close.assert_not_called()
        self.assertEqual(self.path.read_bytes(), self.final)

    def test_saved_preview_failure_keeps_final_source_and_window(self):
        payloads = iter([self.old_tag, self.new_tag])
        def office(action, *_): return next(payloads) if action == 'payload' else 'updated'
        with patch.object(chemoffice, 'chem_snapshot', side_effect=self.snapshot), \
             patch.object(chemoffice, 'office_preview', side_effect=lambda _, p: p), \
             patch.object(chemoffice, 'office', side_effect=office), \
             patch.object(chemoffice, 'verify_saved_figure', side_effect=RuntimeError('preview mismatch')), \
             patch.object(chemoffice, 'chem_close') as close:
            with self.assertRaisesRegex(RuntimeError, 'preview mismatch'): self.bridge.finish('command-w')
            close.assert_not_called()
        self.assertEqual(self.path.read_bytes(), self.final)
        self.assertEqual(self.bridge.session['originalTag'], self.new_tag)
        self.assertFalse(json.loads(chemoffice.STATE.read_text())['busy'])
