import importlib.util
from pathlib import Path
import unittest

import pandas as pd


MODULE_PATH = Path(__file__).parents[1] / "python" / "transformation" / "transform_tac_data.py"
SPEC = importlib.util.spec_from_file_location("transform_tac_data", MODULE_PATH)
transform = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(transform)


class TrustFlagTests(unittest.TestCase):
    def test_ebitda_rag_thresholds_are_unique_and_preserve_missing(self):
        frame = pd.DataFrame({
            "total_income_000s": [500_000, 1_500_000, 500_000, 500_000, 500_000],
            "sector": ["Acute"] * 5,
            "pay_pct_income": [60.0, 66.0, 60.0, 60.0, 60.0],
            "ebitda_margin_pct": [-1.0, 1.9, 2.0, 5.0, None],
        })

        result = transform.add_trust_flags(frame)

        self.assertEqual(result["ebitda_rag"].iloc[:4].tolist(), [
            "Red", "Red", "Amber", "Green",
        ])
        self.assertTrue(pd.isna(result["ebitda_rag"].iloc[4]))
        self.assertEqual(result["is_large"].tolist(), [0, 1, 0, 0, 0])
        self.assertEqual(result["pay_pressure_flag"].tolist(), [0, 1, 0, 0, 0])


if __name__ == "__main__":
    unittest.main()
