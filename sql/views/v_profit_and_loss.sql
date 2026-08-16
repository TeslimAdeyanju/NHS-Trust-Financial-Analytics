-- v_profit_and_loss
-- Full statutory Profit & Loss (Statement of Comprehensive Income) from TAC02 SoCI/SOC
-- One row per trust per financial year
-- All monetary values in £000s
--
-- This is the full-detail counterpart to v_income_expenditure (which stays summary-only --
-- it feeds v_kpis and v_trust_annual_scorecard and shouldn't change shape under them).
--
-- Excludes SOC0200-SOC0250: a memo note on surplus attribution between non-controlling
-- interest and owners of the parent. Not part of the primary statement, and blank for the
-- great majority of single-entity NHS trusts.
--
-- Sub-codes used (see agent_docs/data_dictionary.md / dim_subcode for the full reference):
--   SCI0100A-SCI0240   Operating result down to surplus/(deficit) for the year
--   SOC0100-SOC0190    Other comprehensive income (OCI), down to total comprehensive income

USE nhs_gold;

DROP VIEW IF EXISTS v_profit_and_loss;
CREATE VIEW v_profit_and_loss AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,

    -- Operating result
    MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END) AS patient_care_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END) AS other_operating_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0125A' THEN f.total_000s END) AS operating_expenses_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s END) AS operating_surplus_000s,

    -- Finance costs
    MAX(CASE WHEN f.sub_code = 'SCI0150'  THEN f.total_000s END) AS finance_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0160'  THEN f.total_000s END) AS finance_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0170'  THEN f.total_000s END) AS pdc_dividend_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0180'  THEN f.total_000s END) AS net_finance_costs_000s,

    -- Other items down to the bottom line
    MAX(CASE WHEN f.sub_code = 'SCI0190A' THEN f.total_000s END) AS other_gains_losses_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0200'  THEN f.total_000s END) AS share_of_associates_jv_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0210'  THEN f.total_000s END) AS gains_losses_transfers_absorption_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0230'  THEN f.total_000s END) AS corporation_tax_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240A' THEN f.total_000s END) AS surplus_continuing_operations_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240B' THEN f.total_000s END) AS surplus_discontinued_operations_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240'  THEN f.total_000s END) AS surplus_for_year_000s,

    -- Other comprehensive income (OCI)
    MAX(CASE WHEN f.sub_code = 'SOC0100'  THEN f.total_000s END) AS oci_impairments_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0110'  THEN f.total_000s END) AS oci_revaluations_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0120'  THEN f.total_000s END) AS oci_share_ci_associates_jv_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0125'  THEN f.total_000s END) AS oci_fv_gains_equity_instruments_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0130'  THEN f.total_000s END) AS oci_other_gains_losses_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0140'  THEN f.total_000s END) AS oci_pension_remeasurement_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0145'  THEN f.total_000s END) AS oci_gain_loss_transfers_absorption_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0150'  THEN f.total_000s END) AS oci_other_reserve_movements_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0160'  THEN f.total_000s END) AS oci_fv_gains_financial_assets_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0170'  THEN f.total_000s END) AS oci_recycling_gains_disposal_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0180'  THEN f.total_000s END) AS oci_foreign_exchange_gains_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0190'  THEN f.total_000s END) AS total_comprehensive_income_000s

FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC02 SoCI'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;
