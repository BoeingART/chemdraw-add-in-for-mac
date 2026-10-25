# SPDX-License-Identifier: Apache-2.0
import sys
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import chemoffice
from metadata import decode


class PasteTransactionTests(unittest.TestCase):
    def test_two_pastes_create_independent_instances_with_exact_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); document = root/'target.docx'; document.touch()
            source = (Path(__file__).parent/'fixtures/clipboard-ethanol.cdx').read_bytes()
            (root/'source.cdx').write_bytes(source)
            Image.new('RGB', (20, 10), 'black').save(root/'preview.png')
            inserted = []
            def vector_export(_, output):
                output.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10"><rect width="20" height="10" fill="black"/></svg>')
            def office(action, host, *args):
                if action == 'context': return str(document)
                self.assertAlmostEqual(float(args[4]), 0.5)
                inserted.append(decode(args[1])); return 'inserted'
            bridge = chemoffice.Bridge()
            with patch.object(chemoffice, 'STATE', root/'state.json'), \
                 patch.object(chemoffice, 'chem_render_vector', side_effect=vector_export), \
                 patch.object(chemoffice, 'office', side_effect=office), \
                 patch.object(chemoffice, 'office_preview', side_effect=lambda _, p: p), \
                 patch.object(chemoffice, 'verify_saved_figure', return_value={}), \
                 patch.object(chemoffice, 'record'):
                bridge.paste('word', root); bridge.paste('word', root)
            self.assertEqual(len(inserted), 2)
            self.assertNotEqual(inserted[0][0], inserted[1][0])
            self.assertEqual(inserted[0][1], source)
            self.assertEqual(inserted[1][1], source)

    def test_unsaved_word_is_refused_before_office_insertion(self):
        with patch.object(chemoffice, 'office', return_value='') as office:
            with self.assertRaisesRegex(RuntimeError, 'Save the target'):
                chemoffice.Bridge().paste('word', '/unused')
            self.assertEqual([call.args[0] for call in office.call_args_list], ['context'])

    def test_unsaved_powerpoint_saves_then_inserts_the_captured_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); document = root/'新演示文稿.pptx'
            source = (Path(__file__).parent/'fixtures/clipboard-ethanol.cdx').read_bytes()
            (root/'source.cdx').write_bytes(source)
            inserted = []
            def export(_, output):
                output.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10"><path d="M0 0L20 10"/></svg>')
            def office(action, host, *args):
                if action == 'context': return '演示文稿1'
                if action == 'save-for-paste':
                    self.assertEqual(json.loads((root/'state.json').read_text()),
                                     {'saveDialogBundle':'com.microsoft.Powerpoint'})
                    document.touch()
                    return str(document)
                self.assertEqual(action, 'insert')
                self.assertEqual(args[3], str(document))
                inserted.append(decode(args[1])[1])
            with patch.object(chemoffice, 'STATE', root/'state.json'), \
                 patch.object(chemoffice, 'office', side_effect=office), \
                 patch.object(chemoffice, 'chem_render_vector', side_effect=export), \
                 patch.object(chemoffice, 'office_preview', side_effect=lambda _, p: p), \
                 patch.object(chemoffice, 'verify_saved_figure', return_value={}), \
                 patch.object(chemoffice, 'record'):
                chemoffice.Bridge().paste('powerpoint', root)
            self.assertEqual(inserted, [source])
            self.assertEqual(json.loads((root/'state.json').read_text()), {})

    def test_save_dialog_cancel_keeps_capture_without_inserting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            captured = root/'source.cdx'; captured.write_bytes(b'captured drawing')
            with patch.object(chemoffice, 'STATE', root/'state.json'), \
                 patch.object(chemoffice, 'office', side_effect=['演示文稿1','']) as office, \
                 patch.object(chemoffice, 'chem_render_vector') as export, \
                 patch.object(chemoffice, 'record'):
                chemoffice.Bridge().paste('powerpoint', root)
            self.assertEqual([call.args[0] for call in office.call_args_list], ['context','save-for-paste'])
            export.assert_not_called()
            self.assertEqual(captured.read_bytes(), b'captured drawing')
            self.assertEqual(json.loads((root/'state.json').read_text()), {})

    def test_save_failure_restores_normal_office_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(chemoffice, 'STATE', root/'state.json'), \
                 patch.object(chemoffice, 'office', side_effect=['演示文稿1',RuntimeError('save failed')]), \
                 patch.object(chemoffice, 'record'):
                with self.assertRaisesRegex(RuntimeError, 'save failed'):
                    chemoffice.Bridge().paste('powerpoint', root)
            self.assertEqual(json.loads((root/'state.json').read_text()), {})

    def test_missing_saved_file_does_not_trigger_save_as_or_insert(self):
        with patch.object(chemoffice, 'office', return_value='/nonexistent/presentation.pptx') as office:
            with self.assertRaisesRegex(RuntimeError, 'Save the target'):
                chemoffice.Bridge().paste('powerpoint', '/unused')
            self.assertEqual([call.args[0] for call in office.call_args_list], ['context'])
