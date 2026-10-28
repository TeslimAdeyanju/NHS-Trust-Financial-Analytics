-- Diagnostic statements: do not silently treat missing amounts as zero.
-- Investigate duplicate trust/year/worksheet/SubCode before trusting MAX pivots.
USE nhs_gold;
DROP VIEW IF EXISTS v_statement_reconciliation;
CREATE VIEW v_statement_reconciliation AS
SELECT p.org_code,p.financial_year,
 p.organisation_name,p.sector,p.region,
 CASE WHEN p.patient_care_income_000s IS NULL OR p.other_operating_income_000s IS NULL OR p.operating_expenses_000s IS NULL OR p.operating_surplus_000s IS NULL THEN NULL
 ELSE p.patient_care_income_000s+p.other_operating_income_000s+p.operating_expenses_000s-p.operating_surplus_000s END AS soci_operating_residual_000s,
 CASE WHEN b.total_assets_employed_000s IS NULL OR b.total_equity_000s IS NULL THEN NULL
 ELSE b.total_assets_employed_000s-b.total_equity_000s END AS sofp_equity_residual_000s,
 CASE WHEN c.operating_cash_flow_000s IS NULL OR c.investing_cash_flow_000s IS NULL OR c.financing_cash_flow_000s IS NULL OR c.net_cash_change_000s IS NULL THEN NULL
 ELSE c.operating_cash_flow_000s+c.investing_cash_flow_000s+c.financing_cash_flow_000s-c.net_cash_change_000s END AS socf_cash_movement_residual_000s,
 CASE WHEN b.cash_and_cash_equivalents_000s IS NULL OR c.closing_cash_000s IS NULL THEN NULL
 ELSE b.cash_and_cash_equivalents_000s-c.closing_cash_000s END AS cash_cross_statement_residual_000s
FROM nhs_gold.v_profit_and_loss p
LEFT JOIN nhs_gold.v_balance_sheet b ON b.org_code=p.org_code AND b.financial_year=p.financial_year
LEFT JOIN nhs_gold.v_cash_flow c ON c.org_code=p.org_code AND c.financial_year=p.financial_year;
