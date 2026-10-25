# SPDX-License-Identifier: Apache-2.0
import sys
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

    def test_unsaved_target_is_refused_before_office_insertion(self):
        with patch.object(chemoffice, 'office', return_value='') as office:
            with self.assertRaisesRegex(RuntimeError, 'Save the target'):
                chemoffice.Bridge().paste('powerpoint', '/unused')
            self.assertEqual([call.args[0] for call in office.call_args_list], ['context'])
