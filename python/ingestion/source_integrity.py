"""Pure source-file integrity helpers used by TAC ingestion and regression tests."""

import hashlib
from pathlib import Path
import re
import unicodedata

import pandas as pd


PROVIDER_NAME_ALIASES_RAW = {
    "South Warwickshire University NHS Foundation Trust":
        "South Warwickshire NHS Foundation Trust",
    "West Hertfordshire Teaching Hospitals NHS Trust":
        "West Hertfordshire Hospitals NHS Trust",
}


def normalise_provider_name(value: str) -> str:
    """Create a deterministic join key without silently applying fuzzy matching."""
    text_value = unicodedata.normalize("NFKC", str(value)).casefold()
    text_value = text_value.replace("&", " and ")
    text_value = text_value.replace("’", "'").replace("‘", "'")
    text_value = re.sub(r"[^a-z0-9]+", " ", text_value)
    return " ".join(text_value.split())


PROVIDER_NAME_ALIASES = {
    normalise_provider_name(source): normalise_provider_name(target)
    for source, target in PROVIDER_NAME_ALIASES_RAW.items()
}


def provider_name_key(value: str) -> str:
    key = normalise_provider_name(value)
    return PROVIDER_NAME_ALIASES.get(key, key)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_validation_counts(
    data_df: pd.DataFrame, provider_df: pd.DataFrame,
) -> dict[str, int]:
    fact_candidates = data_df[(data_df["year_type"] == "CY") & data_df["total"].notna()]
    duplicate_mask = data_df.duplicated(
        subset=[
            "organisation_name", "worksheet_name", "table_id", "main_code",
            "row_num", "sub_code",
        ],
        keep=False,
    )
    duplicate_fact_key_mask = fact_candidates.duplicated(
        subset=["provider_name_key", "main_code", "sub_code"], keep=False
    )
    provider_code_counts = provider_df.groupby("provider_name_key")["org_code"].nunique()
    ambiguous_keys = set(provider_code_counts[provider_code_counts > 1].index)
    duplicate_provider_mask = provider_df.duplicated(
        subset=["provider_name_key", "org_code"], keep=False
    )
    provider_keys = set(provider_df["provider_name_key"])
    unmatched_mask = ~fact_candidates["provider_name_key"].isin(provider_keys)
    return {
        "source_rows": len(data_df),
        "current_year_rows": int((data_df["year_type"] == "CY").sum()),
        "fact_candidate_rows": len(fact_candidates),
        "provider_rows": len(provider_df),
        "duplicate_rows": int(duplicate_mask.sum()),
        "duplicate_fact_key_rows": int(duplicate_fact_key_mask.sum()),
        "unmatched_provider_rows": int(unmatched_mask.sum()),
        "ambiguous_provider_keys": len(ambiguous_keys),
        "duplicate_provider_rows": int(duplicate_provider_mask.sum()),
    }
