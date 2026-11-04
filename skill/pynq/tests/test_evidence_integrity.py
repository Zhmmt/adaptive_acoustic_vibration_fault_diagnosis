"""Verify the evidence manifest against original included bytes."""
import hashlib
import json
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]


class EvidenceIntegrityTests(unittest.TestCase):
    def test_all_source_snapshots(self):
        obj = json.loads((SKILL / 'configs/source_evidence.json').read_text(encoding='utf8'))
        for role, entry in obj['snapshots'].items():
            with self.subTest(role=role):
                p = SKILL / entry['source']
                self.assertTrue(p.is_file())
                self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(), entry['sha256'])


if __name__ == '__main__':
    unittest.main()
