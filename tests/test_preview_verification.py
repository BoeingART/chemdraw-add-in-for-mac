# SPDX-License-Identifier: Apache-2.0
import io
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from PIL import Image, ImageDraw
from verification import preview_agreement


def image_bytes(mark):
    image = Image.new('RGB', (160, 100), 'white')
    draw = ImageDraw.Draw(image)
    draw.line((15, 70, 60, 25, 105, 70), fill='black', width=3)
    draw.text((100, 75), mark, fill='black')
    stream = io.BytesIO()
    image.save(stream, format='PNG')
    return stream.getvalue()


class PreviewVerificationTests(unittest.TestCase):
    def test_identical_render_is_accepted(self):
        report = preview_agreement(image_bytes('NH2'), image_bytes('NH2'))
        self.assertEqual(report['ink_coverage'], [1.0, 1.0])

    def test_visibly_different_label_is_rejected(self):
        with self.assertRaises(RuntimeError):
            preview_agreement(image_bytes('NH2'), image_bytes('OH'))
