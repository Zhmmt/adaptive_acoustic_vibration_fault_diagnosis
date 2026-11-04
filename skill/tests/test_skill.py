from pathlib import Path
import unittest,tempfile,subprocess,sys,json
ROOT=Path(__file__).resolve().parents[2]
class AuditTests(unittest.TestCase):
 def test_timing_final(self):
  p=subprocess.run([sys.executable,str(ROOT/'skill/tools/timing_audit.py'),str(ROOT/'build/reports/optimized/timing_summary.rpt'),'--require-pass'],capture_output=True,text=True)
  self.assertEqual(p.returncode,0,p.stdout+p.stderr)
  self.assertIn('"pass_internal_timing": true',p.stdout)
 def test_timing_baseline_fails(self):
  p=subprocess.run([sys.executable,str(ROOT/'skill/tools/timing_audit.py'),str(ROOT/'build/reports/baseline/timing_summary.rpt'),'--require-pass'],capture_output=True,text=True)
  self.assertEqual(p.returncode,1,p.stdout+p.stderr)
 def test_hwh_contract(self):
  p=subprocess.run([sys.executable,str(ROOT/'skill/tools/hwh_contract.py'),str(ROOT/'baseline_artifacts/board_tested_original_hwh'),str(ROOT/'board/deploy/rs555_final.hwh')],capture_output=True,text=True)
  # ABI address and datapath width are preserved; DMA length width is intentionally 14 -> 16.
  self.assertEqual(p.returncode,1,p.stdout+p.stderr)
  output=json.loads(p.stdout)
  self.assertFalse(output['compatible'])
  diffs=output['differences']
  self.assertEqual(len(diffs),1)
  self.assertEqual(diffs[0]['ip'],'axi_dma_audio')
  old,new=diffs[0]['old'],diffs[0]['new']
  self.assertEqual(old['C_SG_LENGTH_WIDTH'],'14')
  self.assertEqual(new['C_SG_LENGTH_WIDTH'],'16')
  self.assertEqual({k:v for k,v in old.items() if k!='C_SG_LENGTH_WIDTH'},
                   {k:v for k,v in new.items() if k!='C_SG_LENGTH_WIDTH'})
 def test_sim_marker(self):
  p=subprocess.run([sys.executable,str(ROOT/'skill/tools/simulation_gate.py'),str(ROOT/'sim/baseline/logs/tach_dynamic_sim.log'),'--marker','PASS'],capture_output=True,text=True)
  self.assertEqual(p.returncode,0,p.stdout+p.stderr)
 def test_bit_manifest(self):
  p=subprocess.run([sys.executable,str(ROOT/'scripts/check_submission.py')],capture_output=True,text=True)
  self.assertEqual(p.returncode,0,p.stdout+p.stderr)
if __name__=='__main__':unittest.main()
