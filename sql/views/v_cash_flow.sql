-- TAC05 SoCF: one row per trust and reporting year, figures in GBP thousands.
-- Preserve signed values; do not treat statement subtotals as additive detail.
USE nhs_gold;
DROP VIEW IF EXISTS v_cash_flow;
CREATE VIEW v_cash_flow AS
SELECT t.org_code,t.organisation_name,t.sector,t.region,t.trust_type,f.financial_year,
 MAX(CASE WHEN f.sub_code='SCF0180' THEN f.total_000s END) AS operating_cash_flow_000s,
 MAX(CASE WHEN f.sub_code='SCF0240' THEN f.total_000s END) AS investing_cash_flow_000s,
 MAX(CASE WHEN f.sub_code='SCF0315' THEN f.total_000s END) AS financing_cash_flow_000s,
 MAX(CASE WHEN f.sub_code='SCF0320' THEN f.total_000s END) AS net_cash_change_000s,
 MAX(CASE WHEN f.sub_code='SCF0325' THEN f.total_000s END) AS opening_cash_restated_000s,
 MAX(CASE WHEN f.sub_code='SCF0355' THEN f.total_000s END) AS closing_cash_000s,
 MAX(CASE WHEN f.sub_code='SCF0350' THEN f.total_000s END) AS absorption_cash_transfer_000s,
 MAX(CASE WHEN f.sub_code='SCF0340' THEN f.total_000s END) AS authorisation_cash_transfer_000s,
 MAX(CASE WHEN f.sub_code='SCF0345' THEN f.total_000s END) AS new_ft_opening_cash_000s
FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON t.org_code=f.org_code
WHERE f.worksheet_name='TAC05 SoCF'
GROUP BY t.org_code,t.organisation_name,t.sector,t.region,t.trust_type,f.financial_year;
