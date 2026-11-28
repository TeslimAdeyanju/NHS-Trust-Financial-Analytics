"""
export_for_analysis.py
----------------------
Exports small, aggregate Parquet files from the Gold views for the analysis layer
(the seaborn notebooks in analysis/notebooks/ and the Shiny app in analysis/app/).

Neither the notebooks nor the app connect to MySQL. They read these files, so the database
is only needed once, here, and the app can be deployed with the files alone.

Output files written to analysis/data/ (git-ignored, regenerate with this script):
    trust_year.parquet         -- one row per trust per year: income, costs, surplus, KPIs,
                                  workforce, cash and balance-sheet headline lines
    expenditure_lines.parquet  -- one row per trust per year per TAC08 operating-expense line
                                  (non-subtotal), with its PAY / NON_PAY grouping

All monetary columns stay in £000s (suffix _000s). Data is annual and actuals only.

Usage:
    python python/reporting/export_for_analysis.py
"""

import logging
import os
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Config ─────────────────────────────────────────────────────────────────

DB_USER     = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST     = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT     = int(os.getenv("DB_PORT", "3306"))
GOLD_DB     = "nhs_gold"   # views live here; nhs_silver.* is qualified where a table is needed

OUT_DIR = Path("analysis/data")


def get_engine():
    if not DB_PASSWORD:
        raise RuntimeError("DB_PASSWORD environment variable is required for MySQL access")
    url = URL.create(
        drivername="mysql+pymysql", username=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT, database=GOLD_DB,
        query={"charset": "utf8mb4"},
    )
    return create_engine(url, echo=False)


def export_query(engine, sql: str, filename: str) -> int:
    with engine.connect() as conn:
        df = pd.read_sql(text(sql), conn)
    df.to_parquet(OUT_DIR / filename, index=False)
    log.info("  Exported %d rows → %s", len(df), filename)
    return len(df)


# ── Exports ────────────────────────────────────────────────────────────────

def export_trust_year(engine) -> None:
    log.info("Exporting trust-year summary...")
    export_query(engine, """
        SELECT
            s.org_code,
            s.organisation_name,
            s.sector,
            s.region,
            s.trust_type,
            s.financial_year,
            CAST(s.total_income_000s        AS DOUBLE) AS total_income_000s,
            CAST(s.patient_care_income_000s AS DOUBLE) AS patient_care_income_000s,
            CAST(s.other_income_000s        AS DOUBLE) AS other_income_000s,
            CAST(s.total_expenditure_000s   AS DOUBLE) AS total_expenditure_000s,
            CAST(s.pay_000s                 AS DOUBLE) AS pay_000s,
            CAST(s.non_pay_000s             AS DOUBLE) AS non_pay_000s,
            CAST(s.drugs_cost_000s          AS DOUBLE) AS drugs_cost_000s,
            CAST(s.clinical_supplies_000s   AS DOUBLE) AS clinical_supplies_000s,
            CAST(s.clinical_negligence_000s AS DOUBLE) AS clinical_negligence_000s,
            CAST(s.depreciation_amort_000s  AS DOUBLE) AS depreciation_amort_000s,
            CAST(s.operating_surplus_000s   AS DOUBLE) AS operating_surplus_000s,
            CAST(s.net_surplus_000s         AS DOUBLE) AS net_surplus_000s,
            CAST(s.ebitda_000s              AS DOUBLE) AS ebitda_000s,
            CAST(s.total_wte                AS DOUBLE) AS total_wte,
            CAST(s.ebitda_margin_pct        AS DOUBLE) AS ebitda_margin_pct,
            CAST(s.pay_pct_income           AS DOUBLE) AS pay_pct_income,
            CAST(s.cost_per_wte_000s        AS DOUBLE) AS cost_per_wte_000s,
            CAST(s.net_surplus_margin_pct   AS DOUBLE) AS net_surplus_margin_pct,
            s.is_deficit,
            s.ebitda_rag,
            CAST(cf.operating_cash_flow_000s       AS DOUBLE) AS operating_cash_flow_000s,
            CAST(cf.closing_cash_000s              AS DOUBLE) AS closing_cash_000s,
            CAST(b.cash_and_cash_equivalents_000s  AS DOUBLE) AS cash_and_cash_equivalents_000s,
            CAST(b.total_current_assets_000s       AS DOUBLE) AS total_current_assets_000s,
            CAST(b.total_current_liabilities_000s  AS DOUBLE) AS total_current_liabilities_000s,
            CAST(b.borrowings_cl_000s              AS DOUBLE) AS borrowings_cl_000s,
            CAST(b.borrowings_ncl_000s             AS DOUBLE) AS borrowings_ncl_000s,
            CAST(b.total_equity_000s               AS DOUBLE) AS total_equity_000s
        FROM v_trust_annual_scorecard s
        LEFT JOIN v_cash_flow cf
            ON s.org_code = cf.org_code AND s.financial_year = cf.financial_year
        LEFT JOIN v_balance_sheet b
            ON s.org_code = b.org_code AND s.financial_year = b.financial_year
        ORDER BY s.financial_year, s.organisation_name
    """, "trust_year.parquet")


def export_expenditure_lines(engine) -> None:
    log.info("Exporting operating expenditure lines...")
    export_query(engine, """
        SELECT
            t.org_code,
            t.organisation_name,
            t.sector,
            t.trust_type,
            f.financial_year,
            f.sub_code,
            sc.description               AS line_item,
            sc.analytics_category,
            CAST(f.total_000s AS DOUBLE) AS amount_000s
        FROM nhs_silver.fct_tac f
        JOIN nhs_silver.dim_trust   t  ON f.org_code = t.org_code
        JOIN nhs_silver.dim_subcode sc ON f.sub_code = sc.sub_code
        WHERE f.worksheet_name = 'TAC08 Op Exp'
          AND f.main_code NOT LIKE '%PY%'
          AND sc.is_subtotal = 0
        ORDER BY f.financial_year, t.org_code, f.sub_code
    """, "expenditure_lines.parquet")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    engine = get_engine()
    export_trust_year(engine)
    export_expenditure_lines(engine)
    log.info("Analysis export complete → %s", OUT_DIR)


if __name__ == "__main__":
    main()
