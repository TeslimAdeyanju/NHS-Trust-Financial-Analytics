-- v_balance_sheet
-- Full statutory Statement of Financial Position (Balance Sheet) from TAC03 SoFP
-- One row per trust per financial year
-- All monetary values in £000s
--
-- Unlike SoCI/EXP, TAC03 SoFP already stores correctly signed values in the raw data
-- (liabilities are negative, e.g. a real trust's BAL1260 "Trade and other payables" = -38490).
-- No sign-flipping needed here -- every column is summed exactly as stored.
--
-- Sub-codes used (see agent_docs/data_dictionary.md / dim_subcode for the full reference):
--   BAL1100-BAL1180   Non-current assets, down to the subtotal
--   BAL1190-BAL1250   Current assets, down to the subtotal
--   BAL1260-BAL1320   Current liabilities, down to the subtotal
--   BAL1330           Total assets less current liabilities
--   BAL1340-BAL1390   Non-current liabilities, down to the subtotal
--   BAL1400           Total assets employed
--   BAL1410-BAL1500   Taxpayers' and others' equity, down to total equity

USE nhs_gold;

DROP VIEW IF EXISTS v_balance_sheet;
CREATE VIEW v_balance_sheet AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,

    -- Non-current assets
    MAX(CASE WHEN f.sub_code = 'BAL1100' THEN f.total_000s END) AS intangible_assets_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1110' THEN f.total_000s END) AS property_plant_equipment_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1115' THEN f.total_000s END) AS right_of_use_assets_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1120' THEN f.total_000s END) AS investment_property_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1130' THEN f.total_000s END) AS investments_jv_associates_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1140' THEN f.total_000s END) AS other_investments_nca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1150' THEN f.total_000s END) AS receivables_nca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1170' THEN f.total_000s END) AS other_assets_nca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1180' THEN f.total_000s END) AS total_non_current_assets_000s,

    -- Current assets
    MAX(CASE WHEN f.sub_code = 'BAL1190' THEN f.total_000s END) AS inventories_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1200' THEN f.total_000s END) AS receivables_ca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1210' THEN f.total_000s END) AS other_investments_ca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1220' THEN f.total_000s END) AS other_assets_ca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1230' THEN f.total_000s END) AS assets_held_for_sale_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1240' THEN f.total_000s END) AS cash_and_cash_equivalents_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1250' THEN f.total_000s END) AS total_current_assets_000s,

    -- Current liabilities
    MAX(CASE WHEN f.sub_code = 'BAL1260' THEN f.total_000s END) AS payables_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1270' THEN f.total_000s END) AS borrowings_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1280' THEN f.total_000s END) AS other_financial_liabilities_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1290' THEN f.total_000s END) AS provisions_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1300' THEN f.total_000s END) AS other_liabilities_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1310' THEN f.total_000s END) AS liabilities_disposal_groups_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1320' THEN f.total_000s END) AS total_current_liabilities_000s,

    MAX(CASE WHEN f.sub_code = 'BAL1330' THEN f.total_000s END) AS total_assets_less_current_liabilities_000s,

    -- Non-current liabilities
    MAX(CASE WHEN f.sub_code = 'BAL1340' THEN f.total_000s END) AS payables_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1350' THEN f.total_000s END) AS borrowings_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1360' THEN f.total_000s END) AS other_financial_liabilities_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1370' THEN f.total_000s END) AS provisions_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1380' THEN f.total_000s END) AS other_liabilities_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1390' THEN f.total_000s END) AS total_non_current_liabilities_000s,

    MAX(CASE WHEN f.sub_code = 'BAL1400' THEN f.total_000s END) AS total_assets_employed_000s,

    -- Taxpayers' and others' equity
    MAX(CASE WHEN f.sub_code = 'BAL1410' THEN f.total_000s END) AS public_dividend_capital_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1420' THEN f.total_000s END) AS revaluation_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1430' THEN f.total_000s END) AS fv_through_oci_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1440' THEN f.total_000s END) AS other_reserves_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1450' THEN f.total_000s END) AS merger_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1460' THEN f.total_000s END) AS income_expenditure_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1470' THEN f.total_000s END) AS non_controlling_interest_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1490' THEN f.total_000s END) AS charitable_fund_reserves_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1500' THEN f.total_000s END) AS total_equity_000s

FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC03 SoFP'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;
