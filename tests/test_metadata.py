# SPDX-License-Identifier: Apache-2.0
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import metadata


class MetadataTests(unittest.TestCase):
    def test_exact_round_trip_with_unicode_and_reaction_annotations(self):
        source = '<CDXML><page><t>Δ → β, 99%</t></page></CDXML>'.encode()
        tag = metadata.encode(source)
        drawing_id, recovered = metadata.decode(tag)
        self.assertEqual(source, recovered)
        self.assertEqual(tag, metadata.encode(recovered, drawing_id))

    def test_corruption_is_rejected_instead_of_committed(self):
        tag = metadata.encode(b'<CDXML><page/></CDXML>')
        parts = tag.split(":", 3)
        parts[2] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'checksum'):
            metadata.decode(':'.join(parts))

    def test_plain_image_and_invalid_xml_are_not_editable_sources(self):
        with self.assertRaises(ValueError): metadata.encode(b'<svg/>')
        with self.assertRaises(ValueError): metadata.decode('ordinary picture')


if __name__ == '__main__': unittest.main()
