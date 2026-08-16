-- v_expenditure_breakdown
-- Operating expenditure by category from TAC08 (Operating Expenditure schedule)
-- One row per trust per financial year
-- All monetary values in £000s
--
-- analytics_category mapping (from dim_subcode):
--   PAY                 — staff and executive director costs, R&D and education staff costs
--   NON_PAY             — clinical/general supplies, drugs, premises, clinical negligence etc.
--   NON_PAY_EXCL_EBITDA — depreciation, amortisation, impairments (excluded from EBITDA numerator)
--
-- Key individual lines:
--   EXP0130   Staff and executive directors costs
--   EXP0170   Drugs costs
--   EXP0240   Depreciation
--   EXP0250   Amortisation
--   EXP0290A  Clinical negligence premium (NHS Resolution)
--   EXP0390   Total operating expenditure

USE nhs_gold;

DROP VIEW IF EXISTS v_expenditure_breakdown;
CREATE VIEW v_expenditure_breakdown AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,

    -- Category totals
    SUM(CASE WHEN sc.analytics_category = 'PAY'
             THEN f.total_000s ELSE 0 END)                      AS pay_000s,

    SUM(CASE WHEN sc.analytics_category = 'NON_PAY'
             THEN f.total_000s ELSE 0 END)                      AS non_pay_000s,

    SUM(CASE WHEN sc.analytics_category = 'NON_PAY_EXCL_EBITDA'
             THEN f.total_000s ELSE 0 END)                      AS depreciation_amort_000s,

    -- Individual lines of interest
    MAX(CASE WHEN f.sub_code = 'EXP0130'  THEN f.total_000s END) AS staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0170'  THEN f.total_000s END) AS drugs_cost_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0240'  THEN f.total_000s END) AS depreciation_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0250'  THEN f.total_000s END) AS amortisation_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0150'  THEN f.total_000s END) AS clinical_supplies_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0160'  THEN f.total_000s END) AS general_supplies_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0290A' THEN f.total_000s END) AS clinical_negligence_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0200'  THEN f.total_000s END) AS establishment_costs_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0210'  THEN f.total_000s END) AS premises_rates_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0220'  THEN f.total_000s END) AS premises_other_000s,

    -- Grand total cross-check
    MAX(CASE WHEN f.sub_code = 'EXP0390'  THEN f.total_000s END) AS total_expenditure_000s

FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t    ON f.org_code  = t.org_code
JOIN nhs_silver.dim_subcode sc ON f.sub_code  = sc.sub_code
WHERE f.worksheet_name = 'TAC08 Op Exp'
GROUP BY
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year;
