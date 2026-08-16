"""
validate_tac_data.py
--------------------
Post-load business rule validation for NHS TAC data across nhs_silver (conformed dims/fact)
and nhs_gold (analytical views).

Runs after load_tac_data.py has populated fct_tac and dim_trust.
Checks are classified as CRITICAL (pipeline should halt) or WARNING (log and continue).

Results are written to data/processed/validation_report.csv.

Usage:
    python python/transformation/validate_tac_data.py
"""

import logging
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Config ──────────────────────────────────────────────────────────────────

DB_USER     = "root"
DB_PASSWORD = "Password1234"
DB_HOST     = "127.0.0.1"
DB_PORT     = 3306
SILVER_DB   = "nhs_silver"   # row-level checks connect here; view-level checks qualify nhs_gold.*

REPORT_PATH = Path("data/processed/validation_report.csv")

# Expected values derived from the published NHS TAC data
EXPECTED = {
    "fact_row_min":           2_000_000,   # should be ~2.18M rows total
    "trust_count_min":        200,          # at least 200 active trusts
    "income_total_2324_bn":   (125, 135),   # £125–135bn total income in 2023/24
    "deficit_trusts_2324":    (100, 140),   # 100–140 trusts in deficit in 2023/24
    "avg_ebitda_2324":        (2.0, 6.0),   # avg EBITDA margin 2–6% in 2023/24
    "avg_pay_pct_acute":      (60, 75),     # pay as % of income, acute sector
}

FINANCIAL_YEARS = ["2021/22", "2022/23", "2023/24"]


# ── Result collector ─────────────────────────────────────────────────────────

@dataclass
class ValidationResult:
    check_name: str
    severity: str           # CRITICAL | WARNING | INFO
    passed: bool
    detail: str
    run_ts: str = field(default_factory=lambda: datetime.utcnow().isoformat())


results: list[ValidationResult] = []


def record(check_name: str, severity: str, passed: bool, detail: str) -> None:
    r = ValidationResult(check_name, severity, passed, detail)
    results.append(r)
    symbol = "PASS" if passed else severity
    log.info("  [%s] %s — %s", symbol, check_name, detail)


# ── Checks ───────────────────────────────────────────────────────────────────

def check_row_counts(conn) -> None:
    """Validate fact table and dimension sizes."""
    fact_count = conn.execute(text("SELECT COUNT(*) FROM fct_tac")).scalar()
    record(
        "fct_tac row count",
        "CRITICAL",
        fact_count >= EXPECTED["fact_row_min"],
        f"{fact_count:,} rows (expected ≥ {EXPECTED['fact_row_min']:,})",
    )

    trust_count = conn.execute(text("SELECT COUNT(*) FROM dim_trust")).scalar()
    record(
        "dim_trust row count",
        "CRITICAL",
        trust_count >= EXPECTED["trust_count_min"],
        f"{trust_count} trusts (expected ≥ {EXPECTED['trust_count_min']})",
    )


def check_year_coverage(conn) -> None:
    """Every expected financial year must be present in the fact table."""
    years_present = {
        row[0]
        for row in conn.execute(text("SELECT DISTINCT financial_year FROM fct_tac"))
    }
    for year in FINANCIAL_YEARS:
        record(
            f"year coverage: {year}",
            "CRITICAL",
            year in years_present,
            f"{'found' if year in years_present else 'MISSING'} in fct_tac",
        )


def check_no_null_org_codes(conn) -> None:
    """No fct_tac rows should have a missing or malformed org_code."""
    null_count = conn.execute(
        text("SELECT COUNT(*) FROM fct_tac WHERE org_code IS NULL OR TRIM(org_code) = ''")
    ).scalar()
    record(
        "no null org_codes in fct_tac",
        "CRITICAL",
        null_count == 0,
        f"{null_count} rows with null/empty org_code",
    )


def check_no_duplicate_keys(conn) -> None:
    """Unique constraint (org_code, financial_year, main_code, sub_code) must hold."""
    dupe_count = conn.execute(text("""
        SELECT COUNT(*) FROM (
            SELECT org_code, financial_year, main_code, sub_code
            FROM fct_tac
            GROUP BY org_code, financial_year, main_code, sub_code
            HAVING COUNT(*) > 1
        ) dupes
    """)).scalar()
    record(
        "no duplicate fact keys",
        "CRITICAL",
        dupe_count == 0,
        f"{dupe_count} duplicate (org_code, year, main_code, sub_code) combinations",
    )


def check_income_totals(conn) -> None:
    """Sector total income for 2023/24 should be within expected range."""
    row = conn.execute(text("""
        SELECT SUM(total_income_000s) / 1e6
        FROM nhs_gold.v_income_expenditure
        WHERE financial_year = '2023/24'
    """)).fetchone()
    total_bn = float(row[0]) if row[0] else 0
    lo, hi = EXPECTED["income_total_2324_bn"]
    record(
        "total income 2023/24 in expected range",
        "WARNING",
        lo <= total_bn <= hi,
        f"£{total_bn:.1f}bn (expected £{lo}–{hi}bn)",
    )


def check_deficit_count(conn) -> None:
    """Number of deficit trusts in 2023/24 should match published NHS England figures."""
    count = conn.execute(text("""
        SELECT SUM(is_deficit)
        FROM nhs_gold.v_trust_annual_scorecard
        WHERE financial_year = '2023/24'
    """)).scalar() or 0
    lo, hi = EXPECTED["deficit_trusts_2324"]
    record(
        "deficit trust count 2023/24",
        "WARNING",
        lo <= int(count) <= hi,
        f"{count} deficit trusts (expected {lo}–{hi})",
    )


def check_ebitda_margin(conn) -> None:
    """Average EBITDA margin 2023/24 should be in the expected band."""
    row = conn.execute(text("""
        SELECT ROUND(AVG(ebitda_margin_pct), 1)
        FROM nhs_gold.v_kpis
        WHERE financial_year = '2023/24'
          AND total_income_000s > 0
    """)).fetchone()
    avg = float(row[0]) if row[0] else 0
    lo, hi = EXPECTED["avg_ebitda_2324"]
    record(
        "avg EBITDA margin 2023/24",
        "WARNING",
        lo <= avg <= hi,
        f"{avg}% (expected {lo}–{hi}%)",
    )


def check_pay_pct_acute(conn) -> None:
    """Average pay % of income for acute trusts should be within NHS benchmark range."""
    row = conn.execute(text("""
        SELECT ROUND(AVG(pay_pct_income), 1)
        FROM nhs_gold.v_kpis
        WHERE financial_year = '2023/24'
          AND sector = 'Acute'
          AND total_income_000s > 0
    """)).fetchone()
    avg = float(row[0]) if row[0] else 0
    lo, hi = EXPECTED["avg_pay_pct_acute"]
    record(
        "avg pay % acute trusts 2023/24",
        "WARNING",
        lo <= avg <= hi,
        f"{avg}% (NHS benchmark {lo}–{hi}%)",
    )


def check_income_expenditure_balance(conn) -> None:
    """For each trust-year, operating_surplus should equal total_income - total_expenditure."""
    mismatched = conn.execute(text("""
        SELECT COUNT(*)
        FROM nhs_gold.v_income_expenditure
        WHERE ABS(
            (total_income_000s - total_expenditure_000s) - operating_surplus_000s
        ) > 1000   -- allow £1m rounding tolerance
          AND operating_surplus_000s IS NOT NULL
    """)).scalar() or 0
    record(
        "income - expenditure = operating surplus",
        "WARNING",
        mismatched == 0,
        f"{mismatched} trust-years where I&E doesn't balance (tolerance £1m)",
    )


def check_wte_plausibility(conn) -> None:
    """Total WTE should be positive and within a plausible range per trust."""
    implausible = conn.execute(text("""
        SELECT COUNT(*)
        FROM nhs_gold.v_workforce
        WHERE total_wte IS NOT NULL
          AND (total_wte <= 0 OR total_wte > 50000)
    """)).scalar() or 0
    record(
        "WTE values plausible (0 < WTE ≤ 50,000)",
        "WARNING",
        implausible == 0,
        f"{implausible} trust-years with implausible WTE",
    )


def check_orphan_fact_rows(conn) -> None:
    """Every org_code in fct_tac must have a matching row in dim_trust."""
    orphans = conn.execute(text("""
        SELECT COUNT(DISTINCT f.org_code)
        FROM fct_tac f
        LEFT JOIN dim_trust t ON f.org_code = t.org_code
        WHERE t.org_code IS NULL
    """)).scalar() or 0
    record(
        "no orphan org_codes in fct_tac",
        "CRITICAL",
        orphans == 0,
        f"{orphans} org_codes in fct_tac not in dim_trust",
    )


# ── Runner ───────────────────────────────────────────────────────────────────

def run_all_checks(conn) -> None:
    checks = [
        check_row_counts,
        check_year_coverage,
        check_no_null_org_codes,
        check_no_duplicate_keys,
        check_orphan_fact_rows,
        check_income_totals,
        check_deficit_count,
        check_ebitda_margin,
        check_pay_pct_acute,
        check_income_expenditure_balance,
        check_wte_plausibility,
    ]
    for check_fn in checks:
        try:
            check_fn(conn)
        except Exception as exc:
            record(check_fn.__name__, "CRITICAL", False, f"Exception: {exc}")


def write_report() -> None:
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    df = pd.DataFrame([vars(r) for r in results])
    df.to_csv(REPORT_PATH, index=False)
    log.info("Validation report written to %s", REPORT_PATH)


def main() -> None:
    url = f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{SILVER_DB}?charset=utf8mb4"
    engine = create_engine(url, echo=False)

    log.info("=" * 60)
    log.info("NHS TAC DATA VALIDATION")
    log.info("=" * 60)

    with engine.connect() as conn:
        run_all_checks(conn)

    write_report()

    passed   = sum(1 for r in results if r.passed)
    failed   = sum(1 for r in results if not r.passed)
    critical = sum(1 for r in results if not r.passed and r.severity == "CRITICAL")

    log.info("=" * 60)
    log.info("RESULTS: %d passed | %d failed (%d critical)", passed, failed, critical)
    log.info("=" * 60)

    if critical > 0:
        log.error("Critical validation failures detected — review validation_report.csv")
        sys.exit(1)


if __name__ == "__main__":
    main()
