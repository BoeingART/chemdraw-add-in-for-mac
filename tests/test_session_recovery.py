# SPDX-License-Identifier: Apache-2.0
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'src'))
import chemoffice
from metadata import encode, decode


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        application = patch.object(chemoffice, 'chem_application', return_value={'bundle':'example.ChemDraw.30'})
        application.start(); self.addCleanup(application.stop)
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.tag = encode(b'<CDXML><page><t>embedded old version</t></page></CDXML>')
        self.uid = decode(self.tag)[0]
        self.draft = self.root/'retained.cdxml'
        self.last_edit = b'<CDXML><page><t>unsynced FINAL Z</t></page></CDXML>'
        self.draft.write_bytes(self.last_edit)
        self.bridge = chemoffice.Bridge()
        self.bridge.session = {'id':self.uid,'host':'word','document':'original.docx','path':str(self.draft),'busy':False}
        for name, value in [('WORK',self.root),('STATE',self.root/'state.json')]:
            mock = patch.object(chemoffice,name,value);mock.start();self.addCleanup(mock.stop)
        logger = patch.object(chemoffice,'record');logger.start();self.addCleanup(logger.stop)

    def test_repeated_double_click_resumes_retained_draft_instead_of_rejecting(self):
        with patch.object(chemoffice,'office',return_value='original.docx'), patch.object(chemoffice,'chem_open') as open_draft:
            self.bridge.begin('word',self.tag)
            open_draft.assert_called_once_with(self.draft)
        self.assertEqual(self.draft.read_bytes(),self.last_edit)

    def test_closed_stale_session_is_archived_before_another_drawing_opens(self):
        new_tag = encode(b'<CDXML><page><t>new drawing</t></page></CDXML>')
        with patch.object(chemoffice,'office',return_value='other.docx'), patch.object(chemoffice,'chem_is_open',return_value=False), patch.object(chemoffice,'chem_open'):
            self.bridge.begin('word',new_tag)
        archived = list((self.root/'recovery').glob('*/retained.cdxml'))
        self.assertEqual(len(archived),1)
        self.assertEqual(archived[0].read_bytes(),self.last_edit)
        self.assertEqual(self.bridge.session['id'],decode(new_tag)[0])

    def test_failed_activation_remains_resumable(self):
        self.bridge.session = None
        with patch.object(chemoffice,'office',return_value='original.docx'), patch.object(chemoffice,'chem_open',side_effect=RuntimeError('not foreground')):
            with self.assertRaisesRegex(RuntimeError,'not foreground'): self.bridge.begin('word',self.tag)
        self.assertEqual(json.loads(chemoffice.STATE.read_text())['id'],self.uid)
        self.assertTrue(Path(self.bridge.session['path']).is_file())
