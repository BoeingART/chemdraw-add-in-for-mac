# SPDX-License-Identifier: Apache-2.0
"""A correct SVG payload is insufficient if Office stretches its shape."""
import sys
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))
from verification import verify_saved_figure, NS


class OfficeGeometryTests(unittest.TestCase):
    def test_square_powerpoint_shape_cannot_pass_with_a_rectangular_svg(self):
        fixture = ROOT / 'examples/vector/Vector PowerPoint.pptx'
        identity = 'c5fa4db0-ce34-471d-9cb2-fe418aad77ee'
        source = (ROOT / f'examples/vector/{identity}.cdx').read_bytes()
        preview = ROOT / f'examples/vector/{identity}.png'
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'stretched.pptx'
            with zipfile.ZipFile(fixture) as original, zipfile.ZipFile(target, 'w') as output:
                for item in original.infolist():
                    data = original.read(item.filename)
                    if item.filename == 'ppt/slides/slide1.xml':
                        root = ET.fromstring(data)
                        extent = root.find('.//p:pic/p:spPr/a:xfrm/a:ext', NS)
                        extent.set('cy', extent.get('cx'))
                        data = ET.tostring(root)
                    output.writestr(item, data)
            with self.assertRaisesRegex(RuntimeError, 'proportions'):
                verify_saved_figure(str(target), 'powerpoint', identity, source, preview)
