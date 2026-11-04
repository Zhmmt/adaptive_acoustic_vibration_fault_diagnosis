"""Compare actual updated RS555 HWH with a fixed contract, not with itself."""
import json
import sys
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL / 'tools'))
from overlay_audit import read_hwh, check_contract, inspect_bit
from make_contract import build_contract


class RealHwhTests(unittest.TestCase):
    def test_hwh_and_dma16(self):
        hwh = SKILL / 'examples/rs555_case/rs555_final.hwh'
        bit = SKILL / 'examples/rs555_case/rs555_final.bit'
        spec = json.loads((SKILL / 'configs/rs555_contract.json').read_text(encoding='utf8'))
        info = read_hwh(hwh)
        errors, _ = check_contract(info, spec)
        self.assertFalse(errors, errors)
        self.assertFalse(inspect_bit(hwh, bit))
        self.assertEqual(info['ips']['axi_dma_audio']['params']['C_SG_LENGTH_WIDTH'], '16')
        self.assertEqual(info['ips']['axi_dma_audio']['C_BASEADDR'], 0x40400000)
        generated = build_contract(info)
        self.assertEqual(generated['instances']['axi_dma_audio']['params']['C_SG_LENGTH_WIDTH'], '16')


if __name__ == '__main__':
    unittest.main()
