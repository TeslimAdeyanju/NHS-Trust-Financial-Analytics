-- NHS Finance Analytics — Data Validation Queries
-- Run these after each data load to confirm integrity
-- All monetary values in £000s

USE nhs_silver;

-- ── 1. Row counts by year and trust type ──────────────────────────────────
SELECT financial_year,
       trust_type,
       COUNT(DISTINCT org_code)  AS providers,
       FORMAT(COUNT(*), 0)       AS total_rows
FROM fct_tac
GROUP BY financial_year, trust_type
ORDER BY financial_year, trust_type;
-- Expected: 140-145 FTs, 66-70 NHS Trusts per year

-- ── 2. Total patient care income by year (SCI0100A) ───────────────────────
SELECT financial_year,
       FORMAT(SUM(total_000s) / 1000000, 1) AS patient_income_bn,
       COUNT(DISTINCT org_code)              AS providers
FROM fct_tac
WHERE sub_code = 'SCI0100A'
GROUP BY financial_year
ORDER BY financial_year;
-- Expected: ~£100bn (2021/22) → ~£118bn (2023/24), rising each year

-- ── 3. Year-on-year I&E summary ───────────────────────────────────────────
SELECT financial_year,
       FORMAT(SUM(patient_care_income_000s) / 1000000, 1) AS patient_income_bn,
       FORMAT(SUM(other_income_000s) / 1000000, 1)         AS other_income_bn,
       FORMAT(SUM(total_income_000s) / 1000000, 1)         AS total_income_bn,
       FORMAT(SUM(total_expenditure_000s) / 1000000, 1)    AS total_exp_bn,
       FORMAT(SUM(operating_surplus_000s) / 1000000, 1)    AS op_surplus_bn,
       COUNT(DISTINCT org_code)                             AS providers
FROM nhs_gold.v_income_expenditure
GROUP BY financial_year
ORDER BY financial_year;
-- Expected trend: income rising ~7-8% per year, expenditure growing faster → worsening surplus

-- ── 4. KPI summary by sector 2023/24 ─────────────────────────────────────
SELECT sector,
       trust_type,
       COUNT(DISTINCT org_code)             AS providers,
       ROUND(AVG(ebitda_margin_pct), 1)     AS avg_ebitda_margin_pct,
       ROUND(AVG(pay_pct_income), 1)        AS avg_pay_pct_income,
       ROUND(AVG(net_surplus_margin_pct), 1) AS avg_net_surplus_pct
FROM nhs_gold.v_kpis
WHERE financial_year = '2023/24'
  AND total_income_000s > 0
GROUP BY sector, trust_type
ORDER BY sector, trust_type;
-- Expected: EBITDA 3-6%, Pay 60-75%, Net surplus typically negative in 2023/24

-- ── 5. Deficit vs surplus count 2023/24 ──────────────────────────────────
SELECT
    COUNT(CASE WHEN operating_surplus_000s <  0 THEN 1 END)  AS deficit_trusts,
    COUNT(CASE WHEN operating_surplus_000s >= 0 THEN 1 END)  AS surplus_trusts,
    COUNT(*)                                                   AS total_trusts,
    FORMAT(SUM(CASE WHEN operating_surplus_000s < 0
               THEN operating_surplus_000s ELSE 0 END) / 1000, 1) AS total_deficit_m,
    FORMAT(SUM(CASE WHEN operating_surplus_000s >= 0
               THEN operating_surplus_000s ELSE 0 END) / 1000, 1) AS total_surplus_m
FROM nhs_gold.v_income_expenditure
WHERE financial_year = '2023/24';
-- Expected: ~60% of trusts in deficit in 2023/24, total sector deficit ~£1.5-2.5bn

-- ── 6. Top 10 trusts by total income 2023/24 ─────────────────────────────
SELECT organisation_name,
       sector,
       trust_type,
       FORMAT(total_income_000s / 1000, 1)        AS total_income_m,
       FORMAT(operating_surplus_000s / 1000, 1)   AS op_surplus_m,
       CONCAT(ROUND(net_surplus_margin_pct, 1), '%') AS net_margin
FROM nhs_gold.v_kpis
WHERE financial_year = '2023/24'
ORDER BY total_income_000s DESC
LIMIT 10;

-- ── 7. Worst performing trusts (largest deficit) 2023/24 ──────────────────
SELECT organisation_name,
       sector,
       trust_type,
       FORMAT(total_income_000s / 1000, 1)        AS total_income_m,
       FORMAT(operating_surplus_000s / 1000, 1)   AS op_surplus_m,
       CONCAT(ROUND(ebitda_margin_pct, 1), '%')   AS ebitda_margin
FROM nhs_gold.v_kpis
WHERE financial_year = '2023/24'
  AND operating_surplus_000s IS NOT NULL
ORDER BY operating_surplus_000s ASC
LIMIT 10;

-- ── 8. Pay and drugs cost breakdown 2023/24 ───────────────────────────────
SELECT financial_year,
       FORMAT(SUM(pay_000s) / 1000000, 1)           AS total_pay_bn,
       FORMAT(SUM(drugs_cost_000s) / 1000000, 1)    AS total_drugs_bn,
       FORMAT(SUM(non_pay_000s) / 1000000, 1)       AS total_non_pay_bn,
       FORMAT(SUM(total_expenditure_000s)/1000000,1) AS total_exp_bn,
       ROUND(SUM(pay_000s) / NULLIF(SUM(total_expenditure_000s),0) * 100, 1) AS pay_pct_exp
FROM nhs_gold.v_expenditure_breakdown
GROUP BY financial_year
ORDER BY financial_year;

-- ── 9. Workforce — total WTE by year ─────────────────────────────────────
SELECT financial_year,
       FORMAT(SUM(total_wte), 0)                   AS total_wte,
       FORMAT(SUM(total_staff_cost_000s)/1000000,1) AS staff_cost_bn,
       ROUND(SUM(total_staff_cost_000s) / NULLIF(SUM(total_wte),0) / 1000, 1) AS avg_cost_per_wte_k
FROM nhs_gold.v_workforce
WHERE total_wte IS NOT NULL
GROUP BY financial_year
ORDER BY financial_year;
-- Expected: ~1-1.2m WTE total, avg cost ~£40-50k per WTE

-- ── 10. Duplicate check ───────────────────────────────────────────────────
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT CONCAT(org_code,'|',financial_year,'|',main_code,'|',sub_code)) AS unique_keys
FROM fct_tac;
-- total_rows should equal unique_keys (no duplicates)
