"""Offline tests: deterministic XML and contract regressions; no physical FPGA assumed."""
import json
import io
import contextlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from overlay_audit import read_hwh, check_contract, inspect_bit, main
from make_contract import build_contract


def fixture(second_base='0x41210000', width='32'):
    return f'''<?xml version="1.0"?>
<EDKSYSTEM><SYSTEMINFO DEVICE="7z020" PACKAGE="clg400"/>
<MODULES>
<MODULE INSTANCE="axi_gpio_ctrl" MODTYPE="axi_gpio" VLNV="xilinx.com:ip:axi_gpio:2.0">
<PARAMETERS><PARAMETER NAME="C_BASEADDR" VALUE="0x41200000"/><PARAMETER NAME="C_HIGHADDR" VALUE="0x4120FFFF"/><PARAMETER NAME="C_GPIO_WIDTH" VALUE="16"/></PARAMETERS></MODULE>
<MODULE INSTANCE="axi_gpio_status0" MODTYPE="axi_gpio" VLNV="xilinx.com:ip:axi_gpio:2.0">
<PARAMETERS><PARAMETER NAME="C_BASEADDR" VALUE="{second_base}"/><PARAMETER NAME="C_HIGHADDR" VALUE="0x4121FFFF"/><PARAMETER NAME="C_GPIO_WIDTH" VALUE="{width}"/></PARAMETERS></MODULE>
</MODULES></EDKSYSTEM>'''

SPEC = {'device': {'DEVICE': '7z020'}, 'instances': {
    'axi_gpio_status0': {'type': 'axi_gpio', 'C_BASEADDR': '0x41210000', 'params': {'C_GPIO_WIDTH': '32'}}}}


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name) / 'design.hwh'
        self.p.write_text(fixture(), encoding='utf-8')

    def test_good_contract(self):
        a = read_hwh(self.p)
        errors, warnings = check_contract(a, SPEC)
        self.assertFalse(errors)
        self.assertEqual(a['ips']['axi_gpio_ctrl']['C_BASEADDR'], 0x41200000)
        self.assertTrue(warnings)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main([str(self.p), '--contract', str(self._spec())]), 0)

    def _spec(self):
        p = self.p.with_suffix('.json')
        p.write_text(json.dumps(SPEC), encoding='utf-8')
        return p

    def test_generated_contract(self):
        baseline = build_contract(read_hwh(self.p))
        errors, _ = check_contract(read_hwh(self.p), baseline)
        self.assertFalse(errors)
        self.assertIn("axi_gpio_ctrl", baseline["instances"])

    def test_wrong_width(self):
        self.p.write_text(fixture(width='8'), encoding='utf-8')
        errors, _ = check_contract(read_hwh(self.p), SPEC)
        self.assertTrue(any('C_GPIO_WIDTH' in x for x in errors))

    def test_overlap(self):
        self.p.write_text(fixture(second_base='0x41200004'), encoding='utf-8')
        errors, _ = check_contract(read_hwh(self.p), SPEC)
        self.assertTrue(any('OVERLAP:' in x for x in errors))

    def test_missing(self):
        errors, _ = check_contract(read_hwh(self.p), {'instances': {'missing_ip': {}}})
        self.assertIn('MISSING: missing_ip', errors)

    def test_bit_pair_validation(self):
        bit = self.p.with_suffix('.bit')
        self.assertTrue(inspect_bit(self.p, bit))
        bit.write_bytes(b'not-a-valid-bitstream')
        self.assertFalse(inspect_bit(self.p, bit))  # file check deliberately does NOT parse BIT
        self.assertTrue(inspect_bit(self.p, bit.with_name('wrong.bit')))

    def test_malformed_xml(self):
        self.p.write_text('<EDKSYSTEM>', encoding='utf-8')
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(main([str(self.p)]), 2)


if __name__ == '__main__':
    unittest.main()
