import importlib.util
from pathlib import Path
import unittest

import pandas as pd


MODULE_PATH = Path(__file__).parents[1] / "python" / "ingestion" / "source_integrity.py"
SPEC = importlib.util.spec_from_file_location("source_integrity", MODULE_PATH)
source_integrity = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(source_integrity)


class ProviderNameTests(unittest.TestCase):
    def test_punctuation_case_and_ampersand_normalise_consistently(self):
        self.assertEqual(
            source_integrity.provider_name_key("Guy's & St Thomas’ NHS Foundation Trust"),
            source_integrity.provider_name_key("GUY’S AND ST THOMAS' NHS FOUNDATION TRUST"),
        )

    def test_reviewed_organisation_aliases_resolve(self):
        self.assertEqual(
            source_integrity.provider_name_key(
                "West Hertfordshire Teaching Hospitals NHS Trust"
            ),
            source_integrity.provider_name_key("West Hertfordshire Hospitals NHS Trust"),
        )
        self.assertEqual(
            source_integrity.provider_name_key(
                "South Warwickshire University NHS Foundation Trust"
            ),
            source_integrity.provider_name_key("South Warwickshire NHS Foundation Trust"),
        )


class SourceValidationTests(unittest.TestCase):
    @staticmethod
    def provider_frame(*names):
        return pd.DataFrame({
            "organisation_name": names,
            "org_code": [f"R{i:02d}" for i in range(len(names))],
            "provider_name_key": [source_integrity.provider_name_key(name) for name in names],
        })

    @staticmethod
    def data_frame(name="Example NHS Trust"):
        return pd.DataFrame({
            "organisation_name": [name],
            "provider_name_key": [source_integrity.provider_name_key(name)],
            "worksheet_name": ["TAC05 SoCF"],
            "table_id": [1],
            "main_code": ["A05CY01"],
            "row_num": [10],
            "sub_code": ["SCF0180"],
            "total": pd.Series([0], dtype="Int64"),
            "year_type": ["CY"],
        })

    def test_zero_is_a_fact_candidate_not_missing(self):
        data = self.data_frame()
        providers = self.provider_frame("Example NHS Trust")
        counts = source_integrity.source_validation_counts(data, providers)
        self.assertEqual(counts["fact_candidate_rows"], 1)
        self.assertEqual(counts["unmatched_provider_rows"], 0)

    def test_blank_total_is_preserved_but_not_promoted(self):
        data = self.data_frame()
        data.loc[0, "total"] = pd.NA
        providers = self.provider_frame("Example NHS Trust")
        counts = source_integrity.source_validation_counts(data, providers)
        self.assertEqual(counts["source_rows"], 1)
        self.assertEqual(counts["fact_candidate_rows"], 0)

    def test_unmatched_provider_rows_are_counted(self):
        data = self.data_frame("Unmapped NHS Trust")
        providers = self.provider_frame("Example NHS Trust")
        counts = source_integrity.source_validation_counts(data, providers)
        self.assertEqual(counts["unmatched_provider_rows"], 1)

    def test_full_source_duplicate_is_counted(self):
        data = pd.concat([self.data_frame(), self.data_frame()], ignore_index=True)
        providers = self.provider_frame("Example NHS Trust")
        counts = source_integrity.source_validation_counts(data, providers)
        self.assertEqual(counts["duplicate_rows"], 2)
        self.assertEqual(counts["duplicate_fact_key_rows"], 2)

    def test_repeated_provider_key_is_only_ambiguous_for_multiple_codes(self):
        data = self.data_frame()
        providers = self.provider_frame("Example NHS Trust", "Example NHS Trust")
        counts = source_integrity.source_validation_counts(data, providers)
        self.assertEqual(counts["ambiguous_provider_keys"], 1)

        providers.loc[1, "org_code"] = providers.loc[0, "org_code"]
        counts = source_integrity.source_validation_counts(data, providers)
        self.assertEqual(counts["ambiguous_provider_keys"], 0)
        self.assertEqual(counts["duplicate_provider_rows"], 2)


if __name__ == "__main__":
    unittest.main()
