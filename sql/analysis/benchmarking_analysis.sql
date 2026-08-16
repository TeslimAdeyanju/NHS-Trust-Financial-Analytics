-- NHS Finance Analytics — Benchmarking and Peer Analysis
-- Cross-trust comparisons, peer groupings, and cost efficiency analysis
-- All monetary values in £000s unless stated
-- Run against nhs_gold database after views are built

USE nhs_gold;


-- ── 1. Trust size bands: income quartile groupings ─────────────────────────
-- Classify trusts by size (income quartile) and show average KPIs per band.
-- Useful for peer benchmarking: small trusts shouldn't be compared to large ones.

WITH size_bands AS (
    SELECT
        org_code,
        financial_year,
        total_income_000s,
        ebitda_margin_pct,
        pay_pct_income,
        cost_per_wte_000s,
        net_surplus_margin_pct,
        is_deficit,
        NTILE(4) OVER (
            PARTITION BY financial_year
            ORDER BY total_income_000s
        ) AS income_quartile
    FROM v_trust_annual_scorecard
    WHERE financial_year = '2023/24'
      AND total_income_000s > 0
)
SELECT
    income_quartile,
    CASE income_quartile
        WHEN 1 THEN 'Q1 — Smallest (<£200m)'
        WHEN 2 THEN 'Q2 — Small–Medium (£200–400m)'
        WHEN 3 THEN 'Q3 — Medium–Large (£400–800m)'
        WHEN 4 THEN 'Q4 — Largest (>£800m)'
    END                                         AS size_band,
    COUNT(*)                                    AS trust_count,
    FORMAT(MIN(total_income_000s) / 1e3, 0)    AS min_income_m,
    FORMAT(MAX(total_income_000s) / 1e3, 0)    AS max_income_m,
    ROUND(AVG(ebitda_margin_pct), 1)            AS avg_ebitda_pct,
    ROUND(AVG(pay_pct_income), 1)               AS avg_pay_pct,
    ROUND(AVG(cost_per_wte_000s), 1)            AS avg_cost_per_wte_000s,
    SUM(is_deficit)                             AS deficit_trusts
FROM size_bands
GROUP BY income_quartile
ORDER BY income_quartile;


-- ── 2. Foundation Trust vs NHS Trust financial performance comparison ───────
-- Foundation Trusts have greater financial autonomy; do they perform better?

SELECT
    financial_year,
    trust_type,
    COUNT(*)                                            AS providers,
    ROUND(AVG(ebitda_margin_pct), 1)                   AS avg_ebitda_pct,
    ROUND(AVG(pay_pct_income), 1)                      AS avg_pay_pct,
    ROUND(AVG(net_surplus_margin_pct), 1)              AS avg_net_surplus_pct,
    SUM(is_deficit)                                     AS deficit_count,
    FORMAT(SUM(operating_surplus_000s) / 1e3, 0)      AS total_surplus_m,
    FORMAT(SUM(total_income_000s) / 1e6, 1)           AS total_income_bn
FROM v_trust_annual_scorecard
WHERE trust_type IS NOT NULL
GROUP BY financial_year, trust_type
ORDER BY financial_year, trust_type;


-- ── 3. Pay pressure heatmap: trusts above sector amber threshold ────────────
-- Identify trusts where pay as % of income exceeds the sector benchmark.
-- Ordered by how far they exceed the threshold (most pressured first).

SELECT
    organisation_name,
    sector,
    region,
    trust_type,
    financial_year,
    CONCAT(pay_pct_income, '%')                        AS pay_pct,
    CASE sector
        WHEN 'Acute'        THEN 65.0
        WHEN 'Mental Health' THEN 70.0
        WHEN 'Community'    THEN 70.0
        WHEN 'Ambulance'    THEN 68.0
        WHEN 'Specialist'   THEN 60.0
        ELSE 65.0
    END                                                AS sector_amber_threshold_pct,
    ROUND(pay_pct_income - CASE sector
        WHEN 'Acute'        THEN 65.0
        WHEN 'Mental Health' THEN 70.0
        WHEN 'Community'    THEN 70.0
        WHEN 'Ambulance'    THEN 68.0
        WHEN 'Specialist'   THEN 60.0
        ELSE 65.0
    END, 1)                                            AS excess_pp,
    CONCAT(ebitda_margin_pct, '%')                     AS ebitda_margin
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
  AND pay_pct_income > CASE sector
        WHEN 'Acute'        THEN 65.0
        WHEN 'Mental Health' THEN 70.0
        WHEN 'Community'    THEN 70.0
        WHEN 'Ambulance'    THEN 68.0
        WHEN 'Specialist'   THEN 60.0
        ELSE 65.0
    END
ORDER BY excess_pp DESC
LIMIT 30;


-- ── 4. Regional financial health summary 2023/24 ───────────────────────────
-- NHS England has 7 regional offices. Which regions are most financially stressed?

SELECT
    region,
    COUNT(DISTINCT org_code)                           AS trusts,
    FORMAT(SUM(total_income_000s) / 1e3, 0)           AS total_income_m,
    FORMAT(SUM(operating_surplus_000s) / 1e3, 0)      AS total_surplus_m,
    ROUND(
        SUM(operating_surplus_000s) / NULLIF(SUM(total_income_000s), 0) * 100,
    1)                                                 AS sector_op_margin_pct,
    ROUND(AVG(ebitda_margin_pct), 1)                   AS avg_ebitda_pct,
    ROUND(AVG(pay_pct_income), 1)                      AS avg_pay_pct,
    SUM(is_deficit)                                     AS deficit_trusts,
    ROUND(SUM(is_deficit) / COUNT(*) * 100, 0)        AS deficit_pct
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
  AND region IS NOT NULL
GROUP BY region
ORDER BY deficit_pct DESC;


-- ── 5. Cost per WTE benchmarking by sector and year ────────────────────────
-- Shows the trend in workforce cost efficiency across sectors.
-- Rising cost per WTE is a major driver of the NHS deficit.

SELECT
    financial_year,
    sector,
    COUNT(*)                                          AS trusts,
    ROUND(AVG(cost_per_wte_000s), 1)                 AS avg_cost_per_wte_000s,
    ROUND(MIN(cost_per_wte_000s), 1)                 AS min_cost_per_wte_000s,
    ROUND(MAX(cost_per_wte_000s), 1)                 AS max_cost_per_wte_000s,
    FORMAT(SUM(total_staff_cost_000s) / 1e3, 0)      AS total_pay_bill_m,
    FORMAT(SUM(total_wte), 0)                         AS total_wte
FROM v_trust_annual_scorecard
WHERE sector IS NOT NULL
  AND total_wte > 0
  AND cost_per_wte_000s IS NOT NULL
GROUP BY financial_year, sector
ORDER BY financial_year, sector;


-- ── 6. Income diversification: private patient income by sector ─────────────
-- Private patient income is one lever trusts can pull to improve finances.
-- Shows which sectors and trusts are best diversified.

SELECT
    organisation_name,
    sector,
    region,
    financial_year,
    FORMAT(private_patient_income_000s / 1e3, 1)     AS private_income_m,
    FORMAT(total_income_000s / 1e3, 0)               AS total_income_m,
    ROUND(
        private_patient_income_000s / NULLIF(total_income_000s, 0) * 100,
    2)                                                AS private_pct
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
  AND private_patient_income_000s > 0
ORDER BY private_patient_income_000s DESC
LIMIT 25;


-- ── 7. Clinical negligence trend: a growing structural cost pressure ─────────
-- NHS Resolution premiums have risen sharply. This query tracks the burden by sector.

SELECT
    financial_year,
    sector,
    COUNT(DISTINCT org_code)                                        AS trusts_reporting,
    FORMAT(SUM(clinical_negligence_000s) / 1e3, 0)                AS total_neg_m,
    ROUND(
        SUM(clinical_negligence_000s) / NULLIF(SUM(total_income_000s), 0) * 100,
    2)                                                              AS neg_pct_income,
    ROUND(AVG(clinical_negligence_000s / NULLIF(total_income_000s, 0) * 100), 2)
                                                                    AS avg_neg_pct_per_trust
FROM v_trust_annual_scorecard
WHERE clinical_negligence_000s IS NOT NULL
  AND sector IS NOT NULL
GROUP BY financial_year, sector
ORDER BY financial_year, neg_pct_income DESC;


-- ── 8. Trusts improving vs deteriorating: year-on-year EBITDA movement ──────
-- Shows which trusts improved their EBITDA margin 2022/23 to 2023/24
-- and which deteriorated most. Useful for longitudinal narrative.

WITH yr_pairs AS (
    SELECT
        a.org_code,
        a.organisation_name,
        a.sector,
        a.region,
        a.ebitda_margin_pct                                     AS ebitda_2324,
        b.ebitda_margin_pct                                     AS ebitda_2223,
        ROUND(a.ebitda_margin_pct - b.ebitda_margin_pct, 1)    AS yoy_change_pp,
        a.is_deficit                                             AS deficit_2324,
        FORMAT(a.total_income_000s / 1e3, 0)                   AS income_m
    FROM v_trust_annual_scorecard a
    JOIN v_trust_annual_scorecard b
        ON a.org_code = b.org_code
       AND a.financial_year = '2023/24'
       AND b.financial_year = '2022/23'
    WHERE a.total_income_000s > 0
      AND b.total_income_000s > 0
)
SELECT
    organisation_name,
    sector,
    region,
    income_m,
    CONCAT(ebitda_2223, '%')     AS ebitda_2223,
    CONCAT(ebitda_2324, '%')     AS ebitda_2324,
    CASE
        WHEN yoy_change_pp > 0 THEN CONCAT('+', yoy_change_pp, 'pp')
        ELSE CONCAT(yoy_change_pp, 'pp')
    END                          AS yoy_change,
    CASE WHEN deficit_2324 = 1 THEN 'DEFICIT' ELSE 'SURPLUS' END AS status_2324
FROM yr_pairs
ORDER BY yoy_change_pp ASC   -- most deteriorated first
LIMIT 30;


-- ── 9. Sickness absence analysis by sector 2023/24 ─────────────────────────
-- Sickness absence is both a cost driver and a quality/capacity risk indicator.

SELECT
    financial_year,
    sector,
    COUNT(*)                                          AS trusts,
    ROUND(AVG(avg_days_lost_per_wte), 1)             AS avg_days_lost_per_wte,
    FORMAT(SUM(total_wte), 0)                         AS total_wte,
    -- Estimated cost of sickness: days lost * avg daily cost (avg pay £000s / 225 working days)
    FORMAT(
        SUM(
            avg_days_lost_per_wte
            * total_wte
            * (cost_per_wte_000s / 225)    -- £000s per working day per WTE
        ) / 1e3,
    0)                                                AS est_sickness_cost_m
FROM v_trust_annual_scorecard
WHERE avg_days_lost_per_wte IS NOT NULL
  AND total_wte > 0
  AND cost_per_wte_000s IS NOT NULL
  AND sector IS NOT NULL
GROUP BY financial_year, sector
ORDER BY financial_year, avg_days_lost_per_wte DESC;


-- ── 10. R&D and education income: academic centre premium ───────────────────
-- Trusts with significant R&D and education income (university hospitals, STPs)
-- tend to have more diversified income and better financial resilience.

SELECT
    organisation_name,
    sector,
    region,
    financial_year,
    FORMAT(rd_income_000s / 1e3, 1)                AS rd_income_m,
    FORMAT(education_training_income_000s / 1e3, 1) AS education_income_m,
    FORMAT((COALESCE(rd_income_000s, 0) + COALESCE(education_training_income_000s, 0)) / 1e3, 1)
                                                     AS rd_edu_total_m,
    ROUND(
        (COALESCE(rd_income_000s, 0) + COALESCE(education_training_income_000s, 0))
        / NULLIF(total_income_000s, 0) * 100,
    1)                                               AS rd_edu_pct_income,
    CONCAT(ebitda_margin_pct, '%')                   AS ebitda_margin
FROM v_trust_annual_scorecard
WHERE financial_year = '2023/24'
  AND (rd_income_000s > 0 OR education_training_income_000s > 0)
ORDER BY rd_edu_total_m DESC
LIMIT 25;
