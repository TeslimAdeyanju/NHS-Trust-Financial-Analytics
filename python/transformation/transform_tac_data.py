"""
transform_tac_data.py
---------------------
Post-load transformation and enrichment of NHS TAC data.

Runs after load_tac_data.py and before export_for_powerbi.py.
Produces cleaned, enriched exports in data/processed/ for downstream use.

Transformations performed:
  1. Sector normalisation — standardise dim_trust.sector values to canonical labels
  2. Trust classification enrichment — flag Foundation Trust status, add is_large flag
  3. Income mix calculation — compute patient/other income split as %
  4. Pay pressure flag — flag trusts where pay % of income exceeds sector benchmark
  5. EBITDA trend — year-on-year EBITDA margin change per trust
  6. Sector benchmarks — aggregated sector summary for benchmarking view
  7. Income detail and expenditure detail exports (long format for Power BI drilldown)

Usage:
    python python/transformation/transform_tac_data.py
"""

import logging
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Config ───────────────────────────────────────────────────────────────────

DB_USER     = "root"
DB_PASSWORD = "Password1234"
DB_HOST     = "127.0.0.1"
DB_PORT     = 3306
GOLD_DB     = "nhs_gold"   # views live here; nhs_silver.* is qualified in queries that need it

PROCESSED_DIR    = Path("data/processed")
POWERBI_DIR      = PROCESSED_DIR / "powerbi_export"

FINANCIAL_YEARS  = ["2021/22", "2022/23", "2023/24"]

# NHS England sector labels — canonical form used throughout the project
SECTOR_ALIASES = {
    "Acute":                      "Acute",
    "ACUTE":                      "Acute",
    "Acute Trust":                 "Acute",
    "Mental Health":               "Mental Health",
    "MENTAL_HEALTH":               "Mental Health",
    "Mental Health Trust":         "Mental Health",
    "Community":                   "Community",
    "COMMUNITY":                   "Community",
    "Community Trust":             "Community",
    "Ambulance":                   "Ambulance",
    "AMBULANCE":                   "Ambulance",
    "Ambulance Trust":             "Ambulance",
    "Specialist":                  "Specialist",
    "SPECIALIST":                  "Specialist",
    "Specialist Trust":            "Specialist",
}

# Pay % of income benchmarks by sector (RAG amber threshold)
PAY_AMBER_THRESHOLD = {
    "Acute":        65.0,
    "Mental Health": 70.0,
    "Community":    70.0,
    "Ambulance":    68.0,
    "Specialist":   60.0,
}

# Trusts with income > £1bn are classified as "large"
LARGE_TRUST_INCOME_THRESHOLD_000S = 1_000_000


def get_engine():
    url = (
        f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}"
        f"/{GOLD_DB}?charset=utf8mb4"
    )
    return create_engine(url, echo=False)


# ── Transformation functions ─────────────────────────────────────────────────

def normalise_sectors(df: pd.DataFrame) -> pd.DataFrame:
    """Standardise sector labels to canonical form."""
    df = df.copy()
    df["sector"] = df["sector"].map(SECTOR_ALIASES).fillna(df["sector"])
    return df


def add_trust_flags(df: pd.DataFrame) -> pd.DataFrame:
    """Add derived flags: is_large, pay_pressure_flag, ebitda_rag."""
    df = df.copy()

    # Large trust flag (income > £1bn)
    df["is_large"] = (df["total_income_000s"] >= LARGE_TRUST_INCOME_THRESHOLD_000S).astype(int)

    # Pay pressure flag — actual pay % exceeds amber threshold for the sector
    amber = df["sector"].map(PAY_AMBER_THRESHOLD)
    df["pay_pressure_flag"] = (df["pay_pct_income"] > amber).astype(int)

    # EBITDA RAG — consistent with kpi_definitions.md thresholds
    df["ebitda_rag"] = pd.cut(
        df["ebitda_margin_pct"],
        bins=[-999, 0, 2, 5, 999],
        labels=["Red", "Red", "Amber", "Green"],
        right=False,
    ).astype(str)
    # Correct the double Red bin edge
    df.loc[df["ebitda_margin_pct"] < 2, "ebitda_rag"] = "Red"
    df.loc[(df["ebitda_margin_pct"] >= 2) & (df["ebitda_margin_pct"] < 5), "ebitda_rag"] = "Amber"
    df.loc[df["ebitda_margin_pct"] >= 5, "ebitda_rag"] = "Green"

    return df


def add_income_mix(df: pd.DataFrame) -> pd.DataFrame:
    """Add patient income % and other income % columns."""
    df = df.copy()
    df["patient_income_pct"] = round(
        df["patient_care_income_000s"] / df["total_income_000s"].replace(0, pd.NA) * 100, 1
    )
    df["other_income_pct"] = round(
        df["other_income_000s"] / df["total_income_000s"].replace(0, pd.NA) * 100, 1
    )
    return df


def add_yoy_ebitda(df: pd.DataFrame) -> pd.DataFrame:
    """Add year-on-year EBITDA margin change per trust (percentage point change)."""
    df = df.copy().sort_values(["org_code", "financial_year"])
    df["ebitda_margin_pct_prior_yr"] = df.groupby("org_code")["ebitda_margin_pct"].shift(1)
    df["ebitda_margin_yoy_pp"] = round(
        df["ebitda_margin_pct"] - df["ebitda_margin_pct_prior_yr"], 1
    )
    return df


# ── Sector benchmark summary ─────────────────────────────────────────────────

def build_sector_benchmarks(scorecard_df: pd.DataFrame) -> pd.DataFrame:
    """
    Aggregate key metrics by sector and financial year.
    Used as the sector_benchmarks.csv export for Power BI benchmarking page.
    """
    agg = (
        scorecard_df
        .groupby(["financial_year", "sector"])
        .agg(
            providers              = ("org_code", "nunique"),
            total_income_000s      = ("total_income_000s", "sum"),
            total_expenditure_000s = ("total_expenditure_000s", "sum"),
            total_surplus_000s     = ("operating_surplus_000s", "sum"),
            total_pay_000s         = ("pay_000s", "sum"),
            total_wte              = ("total_wte", "sum"),
            avg_ebitda_margin_pct  = ("ebitda_margin_pct", "mean"),
            median_ebitda_pct      = ("ebitda_margin_pct", "median"),
            avg_pay_pct_income     = ("pay_pct_income", "mean"),
            avg_cost_per_wte_000s  = ("cost_per_wte_000s", "mean"),
            deficit_trusts         = ("is_deficit", "sum"),
        )
        .reset_index()
    )
    agg["avg_ebitda_margin_pct"] = agg["avg_ebitda_margin_pct"].round(1)
    agg["median_ebitda_pct"]     = agg["median_ebitda_pct"].round(1)
    agg["avg_pay_pct_income"]    = agg["avg_pay_pct_income"].round(1)
    agg["avg_cost_per_wte_000s"] = agg["avg_cost_per_wte_000s"].round(1)

    # Sector-level pay % (not average of averages — weighted)
    agg["sector_pay_pct"] = round(
        agg["total_pay_000s"] / agg["total_income_000s"].replace(0, pd.NA) * 100, 1
    )
    return agg


# ── Income and expenditure detail exports ────────────────────────────────────

def build_income_detail(engine) -> pd.DataFrame:
    """
    Long-format income by TAC subcode for Power BI income drilldown.
    Joins fct_tac (income subcodes only) with dim_trust and dim_subcode.
    """
    sql = """
        SELECT
            t.org_code,
            t.organisation_name,
            t.sector,
            t.region,
            t.trust_type,
            f.financial_year,
            f.worksheet_name,
            f.sub_code,
            sc.description      AS sub_code_description,
            sc.is_subtotal,
            f.total_000s        AS value_000s
        FROM nhs_silver.fct_tac f
        JOIN nhs_silver.dim_trust   t  ON f.org_code = t.org_code
        JOIN nhs_silver.dim_subcode sc ON f.sub_code = sc.sub_code
        WHERE f.worksheet_name IN ('TAC06 Op Inc 1', 'TAC07 Op Inc 2', 'TAC02 SoCI')
          AND sc.analytics_category IN ('PATIENT_INCOME', 'OTHER_INCOME', 'TOTAL_INCOME')
        ORDER BY f.financial_year, t.org_code, f.worksheet_name, f.sub_code
    """
    df = pd.read_sql(sql, engine)
    log.info("  Income detail: %d rows", len(df))
    return df


def build_expenditure_detail(engine) -> pd.DataFrame:
    """
    Long-format expenditure by TAC subcode for Power BI expenditure drilldown.
    """
    sql = """
        SELECT
            t.org_code,
            t.organisation_name,
            t.sector,
            t.region,
            t.trust_type,
            f.financial_year,
            f.sub_code,
            sc.description      AS sub_code_description,
            sc.analytics_category,
            sc.is_subtotal,
            f.total_000s        AS value_000s
        FROM nhs_silver.fct_tac f
        JOIN nhs_silver.dim_trust   t  ON f.org_code = t.org_code
        JOIN nhs_silver.dim_subcode sc ON f.sub_code = sc.sub_code
        WHERE f.worksheet_name = 'TAC08 Op Exp'
        ORDER BY f.financial_year, t.org_code, f.sub_code
    """
    df = pd.read_sql(sql, engine)
    log.info("  Expenditure detail: %d rows", len(df))
    return df


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    POWERBI_DIR.mkdir(parents=True, exist_ok=True)
    engine = get_engine()

    log.info("=" * 60)
    log.info("NHS TAC DATA TRANSFORMATION")
    log.info("=" * 60)

    # Load scorecard view
    log.info("Loading v_trust_annual_scorecard...")
    scorecard = pd.read_sql("SELECT * FROM v_trust_annual_scorecard", engine)
    log.info("  %d rows loaded", len(scorecard))

    # Apply transformations
    log.info("Applying transformations...")
    scorecard = (
        scorecard
        .pipe(normalise_sectors)
        .pipe(add_trust_flags)
        .pipe(add_income_mix)
        .pipe(add_yoy_ebitda)
    )

    # Sector benchmarks
    log.info("Building sector benchmarks...")
    benchmarks = build_sector_benchmarks(scorecard)

    # Detail tables
    log.info("Building income detail...")
    income_detail = build_income_detail(engine)

    log.info("Building expenditure detail...")
    expenditure_detail = build_expenditure_detail(engine)

    # Dimension tables
    dim_trust = pd.read_sql("SELECT * FROM nhs_silver.dim_trust", engine)
    dim_year  = pd.read_sql("SELECT * FROM nhs_silver.dim_financial_year", engine)

    # ── Write exports ────────────────────────────────────────────────────────
    exports = {
        "kpis.csv":                    scorecard[[
            "org_code", "organisation_name", "sector", "region", "trust_type",
            "financial_year", "total_income_000s", "ebitda_000s", "ebitda_margin_pct",
            "pay_000s", "pay_pct_income", "total_wte", "cost_per_wte_000s",
            "net_surplus_000s", "net_surplus_margin_pct", "is_deficit",
            "is_large", "pay_pressure_flag", "ebitda_rag", "ebitda_margin_yoy_pp",
        ]],
        "ie_summary.csv":              scorecard[[
            "org_code", "financial_year", "total_income_000s", "patient_care_income_000s",
            "other_income_000s", "total_expenditure_000s", "operating_surplus_000s",
            "net_surplus_000s", "patient_income_pct", "other_income_pct",
        ]],
        "expenditure_breakdown.csv":   scorecard[[
            "org_code", "financial_year", "pay_000s", "non_pay_000s",
            "depreciation_amort_000s", "drugs_cost_000s", "clinical_negligence_000s",
            "clinical_supplies_000s", "general_supplies_000s",
        ]],
        "workforce.csv":               scorecard[[
            "org_code", "financial_year", "total_wte", "total_staff_cost_000s",
            "gross_staff_cost_000s", "medical_wte", "nursing_wte",
        ]],
        "sector_benchmarks.csv":       benchmarks,
        "income_detail.csv":           income_detail,
        "expenditure_detail.csv":      expenditure_detail,
        "dim_trust.csv":               dim_trust,
        "dim_financial_year.csv":      dim_year,
    }

    for filename, df in exports.items():
        path = POWERBI_DIR / filename
        # Drop columns that aren't in the df (scorecard may not have all columns)
        df = df[[c for c in df.columns if c in df.columns]]
        df.to_csv(path, index=False)
        log.info("  Written: %s (%d rows)", filename, len(df))

    log.info("=" * 60)
    log.info("TRANSFORMATION COMPLETE — %d files written to %s", len(exports), POWERBI_DIR)
    log.info("=" * 60)


if __name__ == "__main__":
    main()
