"""Golden references for signed stereo unpacking and invalid input handling."""
import struct
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from pcm_decode import decode_words, channel_summary


class DecodeTests(unittest.TestCase):
    def test_known_words(self):
        data = struct.pack('<I', 0x00010002) + struct.pack('<I', 0xFFFF8000) + struct.pack('<I', 0x7FFF0000)
        self.assertEqual(decode_words(data), [(2, 1), (-32768, -1), (0, 32767)])
        self.assertEqual(decode_words(data, 'ba'), [(1, 2), (-1, -32768), (32767, 0)])

    def test_no_truncated_data(self):
        with self.assertRaises(ValueError):
            decode_words(b'\x01\x02\x03')

    def test_summary(self):
        s = channel_summary([-32768, 0, 2])
        self.assertEqual(s['peak_abs'], 32768)
        self.assertEqual(s['count'], 3)
        self.assertEqual(channel_summary([])['count'], 0)


if __name__ == '__main__':
    unittest.main()
