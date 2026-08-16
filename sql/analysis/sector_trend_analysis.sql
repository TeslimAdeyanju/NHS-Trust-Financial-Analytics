-- NHS Finance Analytics — Sector Trend Analysis Queries
-- Ready-to-run analytical queries for portfolio presentation
-- All monetary values in £000s

USE nhs_gold;

-- ── 1. National I&E trend 2021/22 to 2023/24 ──────────────────────────────
SELECT
    financial_year,
    FORMAT(SUM(total_income_000s)       / 1e6, 1)  AS total_income_bn,
    FORMAT(SUM(total_expenditure_000s)  / 1e6, 1)  AS total_expenditure_bn,
    FORMAT(SUM(operating_surplus_000s)  / 1e3, 0)  AS op_surplus_m,
    FORMAT(SUM(net_surplus_000s)        / 1e3, 0)  AS net_surplus_m,
    ROUND(AVG(ebitda_margin_pct), 1)               AS avg_ebitda_pct,
    SUM(is_deficit)                                AS deficit_trusts,
    COUNT(*)                                       AS total_trusts
FROM v_trust_annual_scorecard
GROUP BY financial_year
ORDER BY financial_year;

-- ── 2. Sector KPI comparison 2023/24 ──────────────────────────────────────
SELECT
    sector,
    trust_type,
    COUNT(*)                                   AS providers,
    FORMAT(SUM(total_income_000s) / 1e3, 0)   AS total_income_m,
    ROUND(AVG(ebitda_margin_pct), 1)           AS avg_ebitda_pct,
    ROUND(AVG(pay_pct_income), 1)              AS avg_pay_pct,
    ROUND(AVG(net_surplus_margin_pct), 1)      AS avg_net_surplus_pct,
    SUM(is_deficit)                            AS deficit_count,
    FORMAT(SUM(CASE WHEN operating_surplus_000s < 0
                    THEN operating_surplus_000s ELSE 0 END) / 1e3, 0) AS total_deficit_m
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
GROUP BY sector, trust_type
ORDER BY sector, trust_type;

-- ── 3. Year-on-year income growth by region ────────────────────────────────
SELECT
    region,
    SUM(CASE WHEN financial_year = '2021/22' THEN total_income_000s END) AS income_2122_000s,
    SUM(CASE WHEN financial_year = '2022/23' THEN total_income_000s END) AS income_2223_000s,
    SUM(CASE WHEN financial_year = '2023/24' THEN total_income_000s END) AS income_2324_000s,
    ROUND(
        (SUM(CASE WHEN financial_year = '2023/24' THEN total_income_000s END)
       - SUM(CASE WHEN financial_year = '2021/22' THEN total_income_000s END))
       / NULLIF(SUM(CASE WHEN financial_year = '2021/22' THEN total_income_000s END), 0) * 100,
    1) AS growth_2yr_pct
FROM v_trust_annual_scorecard
WHERE region IS NOT NULL
GROUP BY region
ORDER BY income_2324_000s DESC;

-- ── 4. EBITDA margin distribution by sector 2023/24 ───────────────────────
SELECT
    sector,
    ROUND(MIN(ebitda_margin_pct), 1)                    AS min_ebitda_pct,
    ROUND(AVG(ebitda_margin_pct), 1)                    AS avg_ebitda_pct,
    ROUND(MAX(ebitda_margin_pct), 1)                    AS max_ebitda_pct,
    COUNT(CASE WHEN ebitda_margin_pct < 0 THEN 1 END)   AS negative_ebitda,
    COUNT(CASE WHEN ebitda_margin_pct BETWEEN 0 AND 2 THEN 1 END) AS low_0_2,
    COUNT(CASE WHEN ebitda_margin_pct BETWEEN 2 AND 5 THEN 1 END) AS mid_2_5,
    COUNT(CASE WHEN ebitda_margin_pct > 5 THEN 1 END)   AS high_gt5
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
  AND sector IS NOT NULL
GROUP BY sector
ORDER BY avg_ebitda_pct DESC;

-- ── 5. Top 20 trusts by income 2023/24 ────────────────────────────────────
SELECT
    RANK() OVER (ORDER BY total_income_000s DESC) AS `rank`,
    organisation_name,
    sector,
    region,
    FORMAT(total_income_000s / 1e3, 0)    AS income_m,
    FORMAT(operating_surplus_000s / 1e3, 0) AS op_surplus_m,
    CONCAT(ebitda_margin_pct, '%')         AS ebitda_margin,
    CONCAT(pay_pct_income, '%')            AS pay_pct,
    CASE WHEN is_deficit = 1 THEN 'DEFICIT' ELSE 'SURPLUS' END AS status
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
ORDER BY total_income_000s DESC
LIMIT 20;

-- ── 6. Worst financial performance 2023/24 (by net surplus margin) ─────────
SELECT
    RANK() OVER (ORDER BY net_surplus_margin_pct ASC) AS deficit_rank,
    organisation_name,
    sector,
    region,
    trust_type,
    FORMAT(total_income_000s / 1e3, 0)     AS income_m,
    FORMAT(net_surplus_000s / 1e3, 0)      AS net_surplus_m,
    CONCAT(net_surplus_margin_pct, '%')    AS net_margin,
    CONCAT(ebitda_margin_pct, '%')         AS ebitda_margin
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
ORDER BY net_surplus_margin_pct ASC
LIMIT 20;

-- ── 7. Pay cost pressure: pay % of income trend ────────────────────────────
SELECT
    financial_year,
    sector,
    ROUND(AVG(pay_pct_income), 1)             AS avg_pay_pct,
    ROUND(SUM(pay_000s) / 1e6, 1)            AS total_pay_bn,
    ROUND(SUM(total_income_000s) / 1e6, 1)   AS total_income_bn,
    ROUND(SUM(pay_000s) / NULLIF(SUM(total_income_000s), 0) * 100, 1) AS sector_pay_pct
FROM v_trust_annual_scorecard
WHERE sector IS NOT NULL
GROUP BY financial_year, sector
ORDER BY financial_year, sector;

-- ── 8. Drugs cost analysis ─────────────────────────────────────────────────
SELECT
    financial_year,
    sector,
    FORMAT(SUM(drugs_cost_000s) / 1e3, 0)                                AS total_drugs_m,
    ROUND(SUM(drugs_cost_000s) / NULLIF(SUM(total_income_000s), 0) * 100, 1) AS drugs_pct_income,
    ROUND(AVG(drugs_cost_000s / NULLIF(total_income_000s, 0) * 100), 1)  AS avg_drugs_pct
FROM v_trust_annual_scorecard
WHERE sector IN ('Acute', 'Specialist')
  AND drugs_cost_000s IS NOT NULL
GROUP BY financial_year, sector
ORDER BY financial_year, sector;

-- ── 9. Clinical negligence: a growing cost pressure ────────────────────────
SELECT
    financial_year,
    FORMAT(SUM(clinical_negligence_000s) / 1e3, 0)                          AS total_neg_m,
    ROUND(SUM(clinical_negligence_000s) / NULLIF(SUM(total_income_000s), 0) * 100, 1) AS neg_pct_income,
    COUNT(DISTINCT org_code)                                                  AS trusts_reporting
FROM v_trust_annual_scorecard
WHERE clinical_negligence_000s IS NOT NULL
GROUP BY financial_year
ORDER BY financial_year;

-- ── 10. Finance income vs finance expense (capital structure pressure) ─────
SELECT
    financial_year,
    FORMAT(SUM(finance_income_000s) / 1e3, 0)                     AS finance_income_m,
    FORMAT(SUM(finance_expense_000s) / 1e3, 0)                    AS finance_expense_m,
    FORMAT(SUM(pdc_dividend_000s) / 1e3, 0)                       AS pdc_dividend_m,
    FORMAT((SUM(finance_income_000s) - SUM(finance_expense_000s)
            - SUM(pdc_dividend_000s)) / 1e3, 0)                   AS net_finance_m
FROM v_trust_annual_scorecard
WHERE finance_income_000s IS NOT NULL
GROUP BY financial_year
ORDER BY financial_year;
