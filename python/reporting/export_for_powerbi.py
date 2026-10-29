"""
export_for_powerbi.py
---------------------
Exports all MySQL analytical views to CSV files for Power BI consumption.

Output files written to data/processed/powerbi_export/:
    dim_trust.csv
    dim_financial_year.csv
    ie_summary.csv           -- v_income_expenditure (per trust per year)
    expenditure_breakdown.csv -- v_expenditure_breakdown
    workforce.csv            -- v_workforce
    kpis.csv                 -- v_kpis (pre-computed KPIs)
    income_detail.csv        -- patient care income subcodes
    expenditure_detail.csv   -- operating expenditure subcodes
    profit_and_loss.csv      -- v_profit_and_loss (full statutory SoCI/SOC detail)
    balance_sheet.csv        -- v_balance_sheet (full statutory SoFP detail)
    cash_flow.csv            -- v_cash_flow (statutory SoCF summary)
    statement_reconciliation.csv -- coverage flags and reconciliation residuals

Usage:
    python python/reporting/export_for_powerbi.py
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
GOLD_DB     = "nhs_gold"   # views live here; nhs_silver.* is qualified in queries that need it

OUT_DIR = Path("data/processed/powerbi_export")


def get_engine():
    if not DB_PASSWORD:
        raise RuntimeError("DB_PASSWORD environment variable is required for MySQL access")
    url = URL.create(
        drivername="mysql+pymysql", username=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT, database=GOLD_DB,
        query={"charset": "utf8mb4"},
    )
    return create_engine(url, echo=False)


# ── Export helpers ──────────────────────────────────────────────────────────

def export_query(engine, sql: str, filename: str, **params) -> int:
    df = pd.read_sql(text(sql), engine.connect(), params=params if params else None)
    out_path = OUT_DIR / filename
    df.to_csv(out_path, index=False, encoding="utf-8-sig")  # utf-8-sig for Excel compat
    log.info("  Exported %d rows → %s", len(df), filename)
    return len(df)


# ── Export functions ────────────────────────────────────────────────────────

def export_dimensions(engine) -> None:
    log.info("Exporting dimension tables...")
    export_query(engine, """
        SELECT org_code, organisation_name, trust_type, sector, region,
               is_foundation, first_year_seen, last_year_seen
        FROM nhs_silver.dim_trust
        ORDER BY organisation_name
    """, "dim_trust.csv")

    export_query(engine, """
        SELECT financial_year, start_date, end_date, year_label_short, is_complete
        FROM nhs_silver.dim_financial_year
        ORDER BY financial_year
    """, "dim_financial_year.csv")


def export_ie_summary(engine) -> None:
    log.info("Exporting income & expenditure summary...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            trust_type,
            financial_year,
            CAST(patient_care_income_000s AS DOUBLE)  AS patient_care_income_000s,
            CAST(other_income_000s AS DOUBLE)          AS other_income_000s,
            CAST(total_income_000s AS DOUBLE)           AS total_income_000s,
            CAST(total_expenditure_000s AS DOUBLE)      AS total_expenditure_000s,
            CAST(operating_surplus_000s AS DOUBLE)      AS operating_surplus_000s,
            CAST(net_surplus_000s AS DOUBLE)            AS net_surplus_000s
        FROM v_income_expenditure
        ORDER BY financial_year, org_code
    """, "ie_summary.csv")


def export_expenditure_breakdown(engine) -> None:
    log.info("Exporting expenditure breakdown...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            trust_type,
            financial_year,
            CAST(pay_000s AS DOUBLE)                   AS pay_000s,
            CAST(non_pay_000s AS DOUBLE)                AS non_pay_000s,
            CAST(depreciation_amort_000s AS DOUBLE)     AS depreciation_amort_000s,
            CAST(drugs_cost_000s AS DOUBLE)             AS drugs_cost_000s,
            CAST(staff_cost_000s AS DOUBLE)             AS staff_cost_000s,
            CAST(total_expenditure_000s AS DOUBLE)      AS total_expenditure_000s
        FROM v_expenditure_breakdown
        ORDER BY financial_year, org_code
    """, "expenditure_breakdown.csv")


def export_workforce(engine) -> None:
    log.info("Exporting workforce data...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            trust_type,
            financial_year,
            CAST(total_staff_cost_000s AS DOUBLE)  AS total_staff_cost_000s,
            CAST(gross_staff_cost_000s AS DOUBLE)   AS gross_staff_cost_000s,
            CAST(total_wte AS DOUBLE)               AS total_wte,
            CAST(medical_wte AS DOUBLE)             AS medical_wte,
            CAST(nursing_wte AS DOUBLE)             AS nursing_wte,
            CAST(admin_estates_wte AS DOUBLE)       AS admin_estates_wte,
            CAST(scientific_tech_wte AS DOUBLE)     AS scientific_tech_wte,
            avg_days_lost_per_wte
        FROM v_workforce
        WHERE total_staff_cost_000s IS NOT NULL
        ORDER BY financial_year, org_code
    """, "workforce.csv")


def export_kpis(engine) -> None:
    log.info("Exporting KPI table...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            trust_type,
            financial_year,
            CAST(total_income_000s AS DOUBLE)          AS total_income_000s,
            CAST(total_expenditure_000s AS DOUBLE)     AS total_expenditure_000s,
            CAST(operating_surplus_000s AS DOUBLE)     AS operating_surplus_000s,
            CAST(net_surplus_000s AS DOUBLE)           AS net_surplus_000s,
            CAST(pay_000s AS DOUBLE)                   AS pay_000s,
            CAST(drugs_cost_000s AS DOUBLE)            AS drugs_cost_000s,
            CAST(depreciation_amort_000s AS DOUBLE)    AS depreciation_amort_000s,
            CAST(ebitda_000s AS DOUBLE)                AS ebitda_000s,
            ebitda_margin_pct,
            pay_pct_income,
            cost_per_wte_000s,
            net_surplus_margin_pct,
            total_wte
        FROM v_kpis
        WHERE total_income_000s > 0
        ORDER BY financial_year, org_code
    """, "kpis.csv")


def export_income_detail(engine) -> None:
    log.info("Exporting patient care income detail...")
    # Patient care income by type and by source (TAC06)
    export_query(engine, """
        SELECT
            t.org_code,
            t.organisation_name,
            t.sector,
            t.trust_type,
            f.financial_year,
            f.sub_code,
            sc.description         AS line_item,
            sc.analytics_category,
            CAST(f.total_000s AS DOUBLE) AS amount_000s
        FROM nhs_silver.fct_tac f
        JOIN nhs_silver.dim_trust   t  ON f.org_code = t.org_code
        JOIN nhs_silver.dim_subcode sc ON f.sub_code = sc.sub_code
        WHERE f.worksheet_name IN ('TAC06 Op Inc 1', 'TAC07 Op Inc 2')
          AND f.main_code NOT LIKE '%PY%'
          AND sc.is_subtotal = 0
        ORDER BY f.financial_year, t.org_code, f.sub_code
    """, "income_detail.csv")


def export_expenditure_detail(engine) -> None:
    log.info("Exporting operating expenditure detail...")
    export_query(engine, """
        SELECT
            t.org_code,
            t.organisation_name,
            t.sector,
            t.trust_type,
            f.financial_year,
            f.sub_code,
            sc.description         AS line_item,
            sc.analytics_category,
            CAST(f.total_000s AS DOUBLE) AS amount_000s
        FROM nhs_silver.fct_tac f
        JOIN nhs_silver.dim_trust   t  ON f.org_code = t.org_code
        JOIN nhs_silver.dim_subcode sc ON f.sub_code = sc.sub_code
        WHERE f.worksheet_name = 'TAC08 Op Exp'
          AND f.main_code NOT LIKE '%PY%'
          AND sc.is_subtotal = 0
        ORDER BY f.financial_year, t.org_code, f.sub_code
    """, "expenditure_detail.csv")


def export_profit_and_loss(engine) -> None:
    log.info("Exporting full statutory profit & loss...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            trust_type,
            financial_year,
            CAST(patient_care_income_000s AS DOUBLE)              AS patient_care_income_000s,
            CAST(other_operating_income_000s AS DOUBLE)           AS other_operating_income_000s,
            CAST(operating_expenses_000s AS DOUBLE)                AS operating_expenses_000s,
            CAST(operating_surplus_000s AS DOUBLE)                 AS operating_surplus_000s,
            CAST(finance_income_000s AS DOUBLE)                    AS finance_income_000s,
            CAST(finance_expense_000s AS DOUBLE)                   AS finance_expense_000s,
            CAST(pdc_dividend_expense_000s AS DOUBLE)              AS pdc_dividend_expense_000s,
            CAST(net_finance_costs_000s AS DOUBLE)                 AS net_finance_costs_000s,
            CAST(other_gains_losses_000s AS DOUBLE)                AS other_gains_losses_000s,
            CAST(share_of_associates_jv_000s AS DOUBLE)            AS share_of_associates_jv_000s,
            CAST(gains_losses_transfers_absorption_000s AS DOUBLE) AS gains_losses_transfers_absorption_000s,
            CAST(corporation_tax_expense_000s AS DOUBLE)           AS corporation_tax_expense_000s,
            CAST(surplus_continuing_operations_000s AS DOUBLE)     AS surplus_continuing_operations_000s,
            CAST(surplus_discontinued_operations_000s AS DOUBLE)   AS surplus_discontinued_operations_000s,
            CAST(surplus_for_year_000s AS DOUBLE)                  AS surplus_for_year_000s,
            CAST(oci_impairments_000s AS DOUBLE)                   AS oci_impairments_000s,
            CAST(oci_revaluations_000s AS DOUBLE)                  AS oci_revaluations_000s,
            CAST(oci_share_ci_associates_jv_000s AS DOUBLE)        AS oci_share_ci_associates_jv_000s,
            CAST(oci_fv_gains_equity_instruments_000s AS DOUBLE)   AS oci_fv_gains_equity_instruments_000s,
            CAST(oci_other_gains_losses_000s AS DOUBLE)            AS oci_other_gains_losses_000s,
            CAST(oci_pension_remeasurement_000s AS DOUBLE)         AS oci_pension_remeasurement_000s,
            CAST(oci_gain_loss_transfers_absorption_000s AS DOUBLE) AS oci_gain_loss_transfers_absorption_000s,
            CAST(oci_other_reserve_movements_000s AS DOUBLE)       AS oci_other_reserve_movements_000s,
            CAST(oci_fv_gains_financial_assets_000s AS DOUBLE)     AS oci_fv_gains_financial_assets_000s,
            CAST(oci_recycling_gains_disposal_000s AS DOUBLE)      AS oci_recycling_gains_disposal_000s,
            CAST(oci_foreign_exchange_gains_000s AS DOUBLE)        AS oci_foreign_exchange_gains_000s,
            CAST(total_comprehensive_income_000s AS DOUBLE)        AS total_comprehensive_income_000s
        FROM v_profit_and_loss
        ORDER BY financial_year, org_code
    """, "profit_and_loss.csv")


def export_balance_sheet(engine) -> None:
    log.info("Exporting full statutory balance sheet...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            trust_type,
            financial_year,
            CAST(intangible_assets_000s AS DOUBLE)               AS intangible_assets_000s,
            CAST(property_plant_equipment_000s AS DOUBLE)        AS property_plant_equipment_000s,
            CAST(right_of_use_assets_000s AS DOUBLE)             AS right_of_use_assets_000s,
            CAST(investment_property_000s AS DOUBLE)             AS investment_property_000s,
            CAST(investments_jv_associates_000s AS DOUBLE)       AS investments_jv_associates_000s,
            CAST(other_investments_nca_000s AS DOUBLE)           AS other_investments_nca_000s,
            CAST(receivables_nca_000s AS DOUBLE)                 AS receivables_nca_000s,
            CAST(other_assets_nca_000s AS DOUBLE)                AS other_assets_nca_000s,
            CAST(total_non_current_assets_000s AS DOUBLE)        AS total_non_current_assets_000s,
            CAST(inventories_000s AS DOUBLE)                     AS inventories_000s,
            CAST(receivables_ca_000s AS DOUBLE)                  AS receivables_ca_000s,
            CAST(other_investments_ca_000s AS DOUBLE)            AS other_investments_ca_000s,
            CAST(other_assets_ca_000s AS DOUBLE)                 AS other_assets_ca_000s,
            CAST(assets_held_for_sale_000s AS DOUBLE)            AS assets_held_for_sale_000s,
            CAST(cash_and_cash_equivalents_000s AS DOUBLE)       AS cash_and_cash_equivalents_000s,
            CAST(total_current_assets_000s AS DOUBLE)            AS total_current_assets_000s,
            CAST(payables_cl_000s AS DOUBLE)                     AS payables_cl_000s,
            CAST(borrowings_cl_000s AS DOUBLE)                   AS borrowings_cl_000s,
            CAST(other_financial_liabilities_cl_000s AS DOUBLE)  AS other_financial_liabilities_cl_000s,
            CAST(provisions_cl_000s AS DOUBLE)                   AS provisions_cl_000s,
            CAST(other_liabilities_cl_000s AS DOUBLE)            AS other_liabilities_cl_000s,
            CAST(liabilities_disposal_groups_000s AS DOUBLE)     AS liabilities_disposal_groups_000s,
            CAST(total_current_liabilities_000s AS DOUBLE)       AS total_current_liabilities_000s,
            CAST(total_assets_less_current_liabilities_000s AS DOUBLE) AS total_assets_less_current_liabilities_000s,
            CAST(payables_ncl_000s AS DOUBLE)                    AS payables_ncl_000s,
            CAST(borrowings_ncl_000s AS DOUBLE)                  AS borrowings_ncl_000s,
            CAST(other_financial_liabilities_ncl_000s AS DOUBLE) AS other_financial_liabilities_ncl_000s,
            CAST(provisions_ncl_000s AS DOUBLE)                  AS provisions_ncl_000s,
            CAST(other_liabilities_ncl_000s AS DOUBLE)           AS other_liabilities_ncl_000s,
            CAST(total_non_current_liabilities_000s AS DOUBLE)   AS total_non_current_liabilities_000s,
            CAST(total_assets_employed_000s AS DOUBLE)           AS total_assets_employed_000s,
            CAST(public_dividend_capital_000s AS DOUBLE)         AS public_dividend_capital_000s,
            CAST(revaluation_reserve_000s AS DOUBLE)             AS revaluation_reserve_000s,
            CAST(fv_through_oci_reserve_000s AS DOUBLE)          AS fv_through_oci_reserve_000s,
            CAST(other_reserves_000s AS DOUBLE)                  AS other_reserves_000s,
            CAST(merger_reserve_000s AS DOUBLE)                  AS merger_reserve_000s,
            CAST(income_expenditure_reserve_000s AS DOUBLE)      AS income_expenditure_reserve_000s,
            CAST(non_controlling_interest_000s AS DOUBLE)        AS non_controlling_interest_000s,
            CAST(charitable_fund_reserves_000s AS DOUBLE)        AS charitable_fund_reserves_000s,
            CAST(total_equity_000s AS DOUBLE)                    AS total_equity_000s
        FROM v_balance_sheet
        ORDER BY financial_year, org_code
    """, "balance_sheet.csv")


def export_cash_flow(engine) -> None:
    log.info("Exporting full statutory cash flow...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            trust_type,
            financial_year,
            CAST(operating_cash_flow_000s AS DOUBLE)       AS operating_cash_flow_000s,
            CAST(investing_cash_flow_000s AS DOUBLE)       AS investing_cash_flow_000s,
            CAST(financing_cash_flow_000s AS DOUBLE)       AS financing_cash_flow_000s,
            CAST(net_cash_change_000s AS DOUBLE)           AS net_cash_change_000s,
            CAST(opening_cash_restated_000s AS DOUBLE)     AS opening_cash_restated_000s,
            CAST(closing_cash_000s AS DOUBLE)              AS closing_cash_000s,
            CAST(absorption_cash_transfer_000s AS DOUBLE)  AS absorption_cash_transfer_000s,
            CAST(authorisation_cash_transfer_000s AS DOUBLE) AS authorisation_cash_transfer_000s,
            CAST(new_ft_opening_cash_000s AS DOUBLE)       AS new_ft_opening_cash_000s
        FROM v_cash_flow
        ORDER BY financial_year, org_code
    """, "cash_flow.csv")


def export_statement_reconciliation(engine) -> None:
    log.info("Exporting three-statement reconciliation...")
    export_query(engine, """
        SELECT
            org_code,
            organisation_name,
            sector,
            region,
            financial_year,
            has_soci,
            has_sofp,
            has_socf,
            CAST(soci_operating_residual_000s AS DOUBLE) AS soci_operating_residual_000s,
            CAST(sofp_equity_residual_000s AS DOUBLE) AS sofp_equity_residual_000s,
            CAST(socf_cash_movement_residual_000s AS DOUBLE) AS socf_cash_movement_residual_000s,
            CAST(cash_cross_statement_residual_000s AS DOUBLE) AS cash_cross_statement_residual_000s
        FROM v_statement_reconciliation
        ORDER BY financial_year, org_code
    """, "statement_reconciliation.csv")


def export_sector_benchmarks(engine) -> None:
    log.info("Exporting sector benchmarks (aggregated)...")
    export_query(engine, """
        SELECT
            financial_year,
            sector,
            trust_type,
            COUNT(DISTINCT org_code)                          AS provider_count,
            ROUND(SUM(total_income_000s) / 1000, 0)          AS total_income_m,
            ROUND(SUM(total_expenditure_000s) / 1000, 0)     AS total_expenditure_m,
            ROUND(SUM(operating_surplus_000s) / 1000, 0)     AS total_op_surplus_m,
            ROUND(AVG(ebitda_margin_pct), 1)                 AS avg_ebitda_margin_pct,
            ROUND(AVG(pay_pct_income), 1)                    AS avg_pay_pct_income,
            ROUND(AVG(net_surplus_margin_pct), 1)            AS avg_net_surplus_margin_pct,
            COUNT(CASE WHEN operating_surplus_000s < 0 THEN 1 END)  AS deficit_count,
            COUNT(CASE WHEN operating_surplus_000s >= 0 THEN 1 END) AS surplus_count
        FROM v_kpis
        WHERE total_income_000s > 0
          AND sector IS NOT NULL
        GROUP BY financial_year, sector, trust_type
        ORDER BY financial_year, sector, trust_type
    """, "sector_benchmarks.csv")


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    engine = get_engine()

    log.info("=" * 60)
    log.info("NHS Finance Analytics — Power BI Export")
    log.info("Output: %s", OUT_DIR.resolve())
    log.info("=" * 60)

    export_dimensions(engine)
    export_ie_summary(engine)
    export_expenditure_breakdown(engine)
    export_workforce(engine)
    export_kpis(engine)
    export_income_detail(engine)
    export_expenditure_detail(engine)
    export_profit_and_loss(engine)
    export_balance_sheet(engine)
    export_cash_flow(engine)
    export_statement_reconciliation(engine)
    export_sector_benchmarks(engine)

    log.info("=" * 60)
    log.info("EXPORT COMPLETE")
    log.info("Files written to: %s", OUT_DIR.resolve())
    log.info("=" * 60)


if __name__ == "__main__":
    main()
