-- v_trust_annual_scorecard
-- One-row-per-trust-per-year "wide" analytical table
-- Combines all key metrics from v_kpis, v_income_expenditure, v_expenditure_breakdown, v_workforce
-- Use for Power BI DirectQuery or as source for CSV export
-- All monetary values in £000s

USE nhs_gold;

DROP VIEW IF EXISTS v_trust_annual_scorecard;
CREATE VIEW v_trust_annual_scorecard AS
SELECT
    -- Identifiers
    k.org_code,
    k.organisation_name,
    k.sector,
    k.region,
    k.trust_type,
    k.financial_year,

    -- ── Income ─────────────────────────────────────────────────────────────
    k.total_income_000s,
    ie.patient_care_income_000s,
    ie.other_income_000s,

    -- Patient care income components (from TAC06)
    MAX(CASE WHEN f.sub_code = 'INC0197' THEN f.total_000s END) AS api_variable_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0198' THEN f.total_000s END) AS api_fixed_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0200' THEN f.total_000s END) AS high_cost_drugs_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0330' THEN f.total_000s END) AS private_patient_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0350' THEN f.total_000s END) AS total_patient_income_tac06_000s,

    -- Other income components (from TAC07)
    MAX(CASE WHEN f.sub_code = 'INC1230A' THEN f.total_000s END) AS rd_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC1240A' THEN f.total_000s END) AS education_training_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC1360'  THEN f.total_000s END) AS total_other_income_tac07_000s,

    -- ── Expenditure ─────────────────────────────────────────────────────────
    k.total_expenditure_000s,
    k.pay_000s,
    ex.non_pay_000s,
    ex.depreciation_amort_000s,
    k.drugs_cost_000s,
    ex.staff_cost_000s,

    -- Key non-pay lines (from TAC08)
    MAX(CASE WHEN f.sub_code = 'EXP0150' THEN f.total_000s END) AS clinical_supplies_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0160' THEN f.total_000s END) AS general_supplies_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0290A' THEN f.total_000s END) AS clinical_negligence_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0240'  THEN f.total_000s END) AS depreciation_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0250'  THEN f.total_000s END) AS amortisation_000s,

    -- ── Surplus / (deficit) ─────────────────────────────────────────────────
    k.operating_surplus_000s,
    k.net_surplus_000s,
    k.ebitda_000s,

    -- ── Finance lines (from TAC02) ──────────────────────────────────────────
    MAX(CASE WHEN f.sub_code = 'SCI0150' THEN f.total_000s END) AS finance_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0160' THEN f.total_000s END) AS finance_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0170' THEN f.total_000s END) AS pdc_dividend_000s,

    -- ── Workforce ───────────────────────────────────────────────────────────
    wf.total_wte,
    wf.total_staff_cost_000s,
    wf.gross_staff_cost_000s,

    -- ── KPIs (pre-computed) ─────────────────────────────────────────────────
    k.ebitda_margin_pct,
    k.pay_pct_income,
    k.cost_per_wte_000s,
    k.net_surplus_margin_pct,

    -- ── Derived flags ───────────────────────────────────────────────────────
    CASE WHEN k.operating_surplus_000s < 0 THEN 1 ELSE 0 END AS is_deficit,
    CASE WHEN k.ebitda_margin_pct < 2 THEN 'Red'
         WHEN k.ebitda_margin_pct < 5 THEN 'Amber'
         ELSE 'Green' END AS ebitda_rag,
    CASE WHEN k.net_surplus_000s < 0 THEN 'Red'
         WHEN k.net_surplus_000s = 0 THEN 'Amber'
         ELSE 'Green' END AS surplus_rag

FROM v_kpis k
JOIN v_income_expenditure ie
    ON k.org_code = ie.org_code AND k.financial_year = ie.financial_year
LEFT JOIN v_expenditure_breakdown ex
    ON k.org_code = ex.org_code AND k.financial_year = ex.financial_year
LEFT JOIN v_workforce wf
    ON k.org_code = wf.org_code AND k.financial_year = wf.financial_year
LEFT JOIN nhs_silver.fct_tac f
    ON k.org_code = f.org_code AND k.financial_year = f.financial_year
    AND f.sub_code IN (
        'INC0197','INC0198','INC0200','INC0330','INC0350',
        'INC1230A','INC1240A','INC1360',
        'EXP0150','EXP0160','EXP0290A','EXP0240','EXP0250',
        'SCI0150','SCI0160','SCI0170'
    )
WHERE k.total_income_000s > 0
GROUP BY
    k.org_code, k.organisation_name, k.sector, k.region, k.trust_type,
    k.financial_year, k.total_income_000s, ie.patient_care_income_000s,
    ie.other_income_000s, k.total_expenditure_000s, k.pay_000s,
    ex.non_pay_000s, ex.depreciation_amort_000s, k.drugs_cost_000s,
    ex.staff_cost_000s, k.operating_surplus_000s, k.net_surplus_000s,
    k.ebitda_000s, wf.total_wte, wf.total_staff_cost_000s,
    wf.gross_staff_cost_000s, k.ebitda_margin_pct, k.pay_pct_income,
    k.cost_per_wte_000s, k.net_surplus_margin_pct;
