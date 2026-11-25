-- Diagnostic statements: do not silently treat missing amounts as zero.
-- Investigate duplicate trust/year/worksheet/SubCode before trusting MAX pivots.
--
-- Closing-cash check: the SoFP reports cash and cash equivalents gross (BAL1240), with bank overdrafts
-- inside borrowings; the SoCF reports them net of overdrafts and committed-facility drawdowns (SCF0355),
-- per IAS 7. The TAC19 CCE cash note bridges the two (CCE0130 + CCE0140 + CCE0150 = CCE0160), so the
-- residual adds CCE0140/CCE0150 back before comparing. TAC19 has two value columns (A19CY01, A19CY02)
-- and trusts may report in either, so both are summed. If a trust-year has no TAC19 rows at all the
-- residual is NULL (unavailable), not a pass; if the note exists but has no overdraft line, that is a
-- genuine zero overdraft.
USE nhs_gold;
DROP VIEW IF EXISTS v_statement_reconciliation;
CREATE VIEW v_statement_reconciliation AS
WITH statement_spine AS (
 SELECT org_code,financial_year FROM nhs_gold.v_profit_and_loss
 UNION
 SELECT org_code,financial_year FROM nhs_gold.v_balance_sheet
 UNION
 SELECT org_code,financial_year FROM nhs_gold.v_cash_flow
),
cash_note AS (
 SELECT f.org_code,f.financial_year,
  COALESCE(SUM(CASE WHEN f.sub_code IN ('CCE0140','CCE0150') THEN f.total_000s END),0) AS cash_overdrafts_000s
 FROM nhs_silver.fct_tac f
 WHERE f.worksheet_name='TAC19 CCE'
 GROUP BY f.org_code,f.financial_year
)
SELECT s.org_code,s.financial_year,
 COALESCE(p.organisation_name,b.organisation_name,c.organisation_name) AS organisation_name,
 COALESCE(p.sector,b.sector,c.sector) AS sector,
 COALESCE(p.region,b.region,c.region) AS region,
 CASE WHEN p.org_code IS NULL THEN 0 ELSE 1 END AS has_soci,
 CASE WHEN b.org_code IS NULL THEN 0 ELSE 1 END AS has_sofp,
 CASE WHEN c.org_code IS NULL THEN 0 ELSE 1 END AS has_socf,
 CASE WHEN p.patient_care_income_000s IS NULL OR p.other_operating_income_000s IS NULL OR p.operating_expenses_000s IS NULL OR p.operating_surplus_000s IS NULL THEN NULL
 ELSE p.patient_care_income_000s+p.other_operating_income_000s+p.operating_expenses_000s-p.operating_surplus_000s END AS soci_operating_residual_000s,
 CASE WHEN b.total_assets_employed_000s IS NULL OR b.total_equity_000s IS NULL THEN NULL
 ELSE b.total_assets_employed_000s-b.total_equity_000s END AS sofp_equity_residual_000s,
 CASE WHEN c.operating_cash_flow_000s IS NULL OR c.investing_cash_flow_000s IS NULL OR c.financing_cash_flow_000s IS NULL OR c.net_cash_change_000s IS NULL THEN NULL
 ELSE c.operating_cash_flow_000s+c.investing_cash_flow_000s+c.financing_cash_flow_000s-c.net_cash_change_000s END AS socf_cash_movement_residual_000s,
 n.cash_overdrafts_000s,
 CASE WHEN b.cash_and_cash_equivalents_000s IS NULL OR c.closing_cash_000s IS NULL OR n.org_code IS NULL THEN NULL
 ELSE b.cash_and_cash_equivalents_000s+n.cash_overdrafts_000s-c.closing_cash_000s END AS cash_cross_statement_residual_000s
FROM statement_spine s
LEFT JOIN nhs_gold.v_profit_and_loss p ON p.org_code=s.org_code AND p.financial_year=s.financial_year
LEFT JOIN nhs_gold.v_balance_sheet b ON b.org_code=s.org_code AND b.financial_year=s.financial_year
LEFT JOIN nhs_gold.v_cash_flow c ON c.org_code=s.org_code AND c.financial_year=s.financial_year
LEFT JOIN cash_note n ON n.org_code=s.org_code AND n.financial_year=s.financial_year;
