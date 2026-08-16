-- v_workforce
-- Staff costs and whole-time equivalent (WTE) numbers from TAC09 (Staff schedule)
-- One row per trust per financial year
--
-- Monetary values in £000s; WTE values are headcount (not £)
--
-- Sub-codes used:
--   STA0220   Total gross staff costs (before recoveries)
--   STA0250   Total staff costs net of recoveries — use this as the primary pay figure
--   STA0310   Medical and dental WTE
--   STA0330   Administration and estates WTE
--   STA0340   Healthcare assistants WTE
--   STA0350   Nursing, midwifery and health visiting WTE
--   STA0370   Scientific, therapeutic and technical WTE
--   STA0410   Total average WTE — most reliable; use for cost per WTE calculation
--   STA0530   Total days lost to sickness absence
--   STA0550   Average working days lost per WTE (sickness rate proxy)
--
-- Note: WTE by staff group (STA0310–STA0370) has known subcode ambiguity in the TAC format
--       for some years. Use STA0410 (total WTE) for benchmarking; treat staff-group WTE
--       breakdown as indicative only.

USE nhs_gold;

DROP VIEW IF EXISTS v_workforce;
CREATE VIEW v_workforce AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,

    -- Staff costs (£000s)
    MAX(CASE WHEN f.sub_code = 'STA0250' THEN f.total_000s END) AS total_staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'STA0220' THEN f.total_000s END) AS gross_staff_cost_000s,

    -- WTE (headcount, not £)
    MAX(CASE WHEN f.sub_code = 'STA0410' THEN f.total_000s END) AS total_wte,
    MAX(CASE WHEN f.sub_code = 'STA0310' THEN f.total_000s END) AS medical_wte,
    MAX(CASE WHEN f.sub_code = 'STA0350' THEN f.total_000s END) AS nursing_wte,
    MAX(CASE WHEN f.sub_code = 'STA0330' THEN f.total_000s END) AS admin_estates_wte,
    MAX(CASE WHEN f.sub_code = 'STA0340' THEN f.total_000s END) AS healthcare_assistant_wte,
    MAX(CASE WHEN f.sub_code = 'STA0370' THEN f.total_000s END) AS scientific_tech_wte,

    -- Sickness absence
    MAX(CASE WHEN f.sub_code = 'STA0530' THEN f.total_000s END) AS total_days_lost_sickness,
    MAX(CASE WHEN f.sub_code = 'STA0550' THEN f.total_000s END) AS avg_days_lost_per_wte

FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC09 Staff'
GROUP BY
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year;
