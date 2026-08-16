-- v_kpis
-- Computed KPIs for each trust per financial year
-- Joins v_income_expenditure + v_expenditure_breakdown + v_workforce
-- All monetary values in £000s; percentages rounded to 1 decimal place
--
-- KPIs implemented (per agent_docs/kpi_definitions.md):
--   1. EBITDA Margin %         — operating surplus + depreciation/amort as % of income
--   2. Pay as % of Income      — total pay costs / total income
--   3. Cost per WTE (£000s)    — net staff costs / total average WTE
--   4. Net Surplus Margin %    — bottom-line surplus / total income
--
-- Not implemented here (require separate data sources):
--   5. CIP Achievement %       — needs cip_tracker data (fct_cip_delivery)
--   6. Budget Variance %       — needs budget data (not in TAC; comes from in-year returns)
--   7. Capital Spend as % of Plan — needs ERIC estates data
--
-- RAG flags:
--   ebitda_rag  — Green ≥5% | Amber 2–5% | Red <2%  (NHS England standard)
--   surplus_rag — Green ≥0% | Amber -2–0% | Red <-2%

USE nhs_gold;

DROP VIEW IF EXISTS v_kpis;
CREATE VIEW v_kpis AS
SELECT
    ie.org_code,
    ie.organisation_name,
    ie.sector,
    ie.region,
    ie.trust_type,
    ie.financial_year,

    -- ── Core financials (passed through from component views) ───────────────
    ie.total_income_000s,
    ie.total_expenditure_000s,
    ie.operating_surplus_000s,
    ie.net_surplus_000s,

    -- ── Expenditure components ───────────────────────────────────────────────
    ex.pay_000s,
    ex.non_pay_000s,
    ex.depreciation_amort_000s,
    ex.staff_cost_000s,
    ex.drugs_cost_000s,
    ex.clinical_negligence_000s,

    -- ── Workforce ────────────────────────────────────────────────────────────
    wf.total_wte,
    wf.medical_wte,
    wf.nursing_wte,
    wf.avg_days_lost_per_wte,

    -- ── KPI 1: EBITDA ────────────────────────────────────────────────────────
    -- EBITDA = operating surplus + depreciation + amortisation
    -- (adds back non-cash charges to get underlying operational cash generation)
    ie.operating_surplus_000s + COALESCE(ex.depreciation_amort_000s, 0)
        AS ebitda_000s,

    ROUND(
        (ie.operating_surplus_000s + COALESCE(ex.depreciation_amort_000s, 0))
        / NULLIF(ie.total_income_000s, 0) * 100,
    1) AS ebitda_margin_pct,

    -- ── KPI 2: Pay as % of Income ────────────────────────────────────────────
    ROUND(
        ex.pay_000s / NULLIF(ie.total_income_000s, 0) * 100,
    1) AS pay_pct_income,

    -- ── KPI 3: Cost per WTE (£000s per WTE) ─────────────────────────────────
    -- Uses net staff cost (STA0250) / total average WTE (STA0410)
    ROUND(
        ex.staff_cost_000s / NULLIF(wf.total_wte, 0),
    1) AS cost_per_wte_000s,

    -- ── KPI 4: Net Surplus Margin % ──────────────────────────────────────────
    ROUND(
        ie.net_surplus_000s / NULLIF(ie.total_income_000s, 0) * 100,
    1) AS net_surplus_margin_pct,

    -- ── Derived flags ────────────────────────────────────────────────────────
    CASE WHEN ie.operating_surplus_000s < 0 THEN 1 ELSE 0 END AS is_deficit,

    CASE
        WHEN ie.operating_surplus_000s + COALESCE(ex.depreciation_amort_000s, 0)
             / NULLIF(ie.total_income_000s, 0) * 100 >= 5  THEN 'Green'
        WHEN ie.operating_surplus_000s + COALESCE(ex.depreciation_amort_000s, 0)
             / NULLIF(ie.total_income_000s, 0) * 100 >= 2  THEN 'Amber'
        ELSE 'Red'
    END AS ebitda_rag,

    CASE
        WHEN ie.net_surplus_000s / NULLIF(ie.total_income_000s, 0) * 100 >= 0   THEN 'Green'
        WHEN ie.net_surplus_000s / NULLIF(ie.total_income_000s, 0) * 100 >= -2  THEN 'Amber'
        ELSE 'Red'
    END AS surplus_rag

FROM v_income_expenditure ie
LEFT JOIN v_expenditure_breakdown ex
    ON ie.org_code = ex.org_code AND ie.financial_year = ex.financial_year
LEFT JOIN v_workforce wf
    ON ie.org_code = wf.org_code AND ie.financial_year = wf.financial_year
WHERE ie.total_income_000s > 0;
