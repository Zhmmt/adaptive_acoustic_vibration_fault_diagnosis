"""Recompute actual provided DMA capture values; does not require an FPGA."""
import hashlib
import sys
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL / 'tools'))
from validate_capture import analyze


class RealCaptureTests(unittest.TestCase):
    def test_uploaded_frame(self):
        capture = SKILL / 'validation/pynq_z2/rs555_audio_frame.bin'
        raw = capture.read_bytes()
        report = analyze(raw)
        self.assertEqual(report['bytes'], 16384)
        self.assertEqual(report['word_count'], 4096)
        self.assertEqual(report['nonzero_words'], 4094)
        self.assertEqual(report['sha256'], '91a6a4f66269d430add33aa63591212940d73a586845afcbdf98f61e2eb26a6e')
        self.assertEqual(report['channel_a']['min'], -143)
        self.assertEqual(report['channel_b']['max'], 1)
        self.assertAlmostEqual(report['channel_correlation'], 0.976617756, places=6)

    def test_invalid_frame(self):
        with self.assertRaises(ValueError):
            analyze(b'\x00')
        with self.assertRaises(ValueError):
            analyze(b'')


if __name__ == '__main__':
    unittest.main()
