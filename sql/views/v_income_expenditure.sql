-- v_income_expenditure
-- Top-level Income & Expenditure summary from TAC02 (Statement of Comprehensive Income)
-- One row per trust per financial year
-- All monetary values in £000s
--
-- Sub-codes used:
--   SCI0100A  Operating income from patient care activities (total)
--   SCI0110A  Other operating income (total)
--   SCI0125A  Operating expenses (total) — stored as positive; ABS() applied here
--   SCI0140A  Operating surplus / (deficit)
--   SCI0240   Surplus / (deficit) for the year (net, after finance lines and PDC)

USE nhs_gold;

DROP VIEW IF EXISTS v_income_expenditure;
CREATE VIEW v_income_expenditure AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,

    -- Income
    MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END)
        AS patient_care_income_000s,

    MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END)
        AS other_income_000s,

    COALESCE(MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END), 0)
        + COALESCE(MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END), 0)
        AS total_income_000s,

    -- Expenditure (SCI0125A is signed negative in the TAC; ABS() gives the cost figure)
    ABS(COALESCE(MAX(CASE WHEN f.sub_code = 'SCI0125A' THEN f.total_000s END), 0))
        AS total_expenditure_000s,

    -- Surplus / (deficit)
    MAX(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s END)
        AS operating_surplus_000s,

    MAX(CASE WHEN f.sub_code = 'SCI0240' THEN f.total_000s END)
        AS net_surplus_000s

FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC02 SoCI'
GROUP BY
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year;
