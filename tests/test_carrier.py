# SPDX-License-Identifier: Apache-2.0
import base64
import io
import sys
import tempfile
import unittest
from pathlib import Path
from PIL import Image, PngImagePlugin
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from carrier import create_carrier, read_carrier, has_vectors, KEY
from metadata import decode, encode


class CarrierTests(unittest.TestCase):
    def test_single_graphic_keeps_exact_native_chemdraw_clipboard_source(self):
        source = (Path(__file__).parent / 'fixtures/clipboard-ethanol.cdx').read_bytes()
        tag = encode(source)
        identity, _ = decode(tag)
        self.assertTrue(tag.startswith('CFM2:'))
        with tempfile.TemporaryDirectory() as directory:
            preview, carrier = Path(directory)/'preview.png', Path(directory)/'figure.svg'
            Image.new('RGBA', (13, 7), (12, 45, 67, 255)).save(preview)
            preview.with_suffix('.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="13" height="7"><rect width="13" height="7" fill="#0c2d43"/></svg>')
            create_carrier(source, preview, identity, carrier)
            self.assertTrue(has_vectors(carrier.read_bytes()))
            recovered_tag, png = read_carrier(carrier.read_bytes())
            self.assertEqual(decode(recovered_tag), (identity, source))
            with Image.open(io.BytesIO(png)) as recovered:
                self.assertEqual(recovered.getpixel((0, 0)), (12, 45, 67, 255))

    def test_raster_only_preview_is_not_silently_inserted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'preview.png'
            Image.new('RGB', (10, 10), 'black').save(path)
            tag = encode(b'<CDXML><page/></CDXML>')
            with self.assertRaisesRegex(ValueError, 'native vector'):
                create_carrier(decode(tag)[1], path, decode(tag)[0], path.with_name('output.svg'))

    def test_corrupted_source_in_visible_graphic_is_rejected(self):
        tag = encode(b'<CDXML><page><t>final Z</t></page></CDXML>')
        fields = tag.split(':');fields[2] = '0' * 64
        metadata = PngImagePlugin.PngInfo();metadata.add_itxt(KEY, ':'.join(fields))
        image = io.BytesIO();Image.new('RGB', (1, 1), 'black').save(image, format='PNG', pnginfo=metadata)
        data = base64.b64encode(image.getvalue()).decode()
        svg = f'<svg xmlns="http://www.w3.org/2000/svg"><image href="data:image/png;base64,{data}"/></svg>'
        with self.assertRaisesRegex(ValueError, 'checksum'): read_carrier(svg.encode())

    def test_ordinary_svg_cannot_become_an_editable_chemical_figure(self):
        with self.assertRaisesRegex(ValueError, 'Expected one'):
            read_carrier(b'<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L1 1"/></svg>')
