"""Pure metadata tests; no PYNQ import and no live DMA operations."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from pynq_s2mm_capture import validate_metadata


class DmaContractTests(unittest.TestCase):
    def setUp(self):
        self.meta = {'parameters': {'C_INCLUDE_SG':'0', 'C_INCLUDE_S2MM':'1',
                                    'C_INCLUDE_MM2S':'0', 'C_SG_LENGTH_WIDTH':'16'}}

    def test_16bit_full_frame(self):
        self.assertEqual(validate_metadata(self.meta, 16384), (16,65535))

    def test_14bit_rejected(self):
        self.meta['parameters']['C_SG_LENGTH_WIDTH'] = '14'
        with self.assertRaisesRegex(ValueError,'exceeds'):
            validate_metadata(self.meta,16384)

    def test_sg_rejected(self):
        self.meta['parameters']['C_INCLUDE_SG'] = '1'
        with self.assertRaisesRegex(ValueError,'simple DMA'):
            validate_metadata(self.meta,16384)


if __name__ == '__main__': unittest.main()
