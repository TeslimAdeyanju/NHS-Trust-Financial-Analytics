-- =============================================================================
-- 02_cost_drivers.sql
-- Board question: which cost lines drive the deficits?
--
-- Compares the first and latest year in the data (derived, never typed in), works
-- straight off the long fact table where a view does not carry the line needed,
-- and ends with a data-quality check that explains why cost per WTE is not used.
-- All money is £000s in the data; columns ending _m are converted for reading.
-- =============================================================================

USE nhs_gold;


-- name: income_vs_cost_growth
-- Growth in combined income and combined expenditure for each sector between the
-- first and latest year. A positive gap means costs outgrew income.
-- Technique: a one-row CTE holding the year range, then a pivot of two years
-- into columns with conditional aggregation.
WITH yrs AS (
    SELECT MIN(financial_year) AS first_year, MAX(financial_year) AS latest_year
    FROM nhs_silver.fct_tac
),
pivoted AS (
    SELECT
        s.sector,
        SUM(CASE WHEN s.financial_year = y.first_year  THEN s.total_income_000s      END) AS income_first,
        SUM(CASE WHEN s.financial_year = y.latest_year THEN s.total_income_000s      END) AS income_latest,
        SUM(CASE WHEN s.financial_year = y.first_year  THEN s.total_expenditure_000s END) AS cost_first,
        SUM(CASE WHEN s.financial_year = y.latest_year THEN s.total_expenditure_000s END) AS cost_latest
    FROM v_kpis s
    CROSS JOIN yrs y
    GROUP BY s.sector
)
SELECT
    sector,
    ROUND(100 * (income_latest / income_first - 1), 1)                        AS income_growth_pct,
    ROUND(100 * (cost_latest   / cost_first   - 1), 1)                        AS cost_growth_pct,
    ROUND(100 * (cost_latest / cost_first - income_latest / income_first), 1) AS growth_gap_pts
FROM pivoted
ORDER BY growth_gap_pts DESC;


-- name: surplus_bridge
-- A bridge (walk) from the national operating result in the first year to the
-- latest year: how much each driver added or took away. The steps add up exactly
-- to the change, because operating surplus = income - total operating expense.
-- Technique: pivot SubCodes out of the long fact table, take first/latest
-- differences, and stack the bridge steps with UNION ALL.
WITH yrs AS (
    SELECT MIN(financial_year) AS first_year, MAX(financial_year) AS latest_year
    FROM nhs_silver.fct_tac
),
year_lines AS (
    SELECT
        f.financial_year,
        SUM(CASE WHEN f.sub_code IN ('SCI0100A', 'SCI0110A') THEN f.total_000s ELSE 0 END) AS income,
        SUM(CASE WHEN f.sub_code = 'EXP0130'                 THEN f.total_000s ELSE 0 END) AS staff,
        SUM(CASE WHEN f.sub_code = 'EXP0170'                 THEN f.total_000s ELSE 0 END) AS drugs,
        SUM(CASE WHEN f.sub_code = 'EXP0260'                 THEN f.total_000s ELSE 0 END) AS impairments,
        SUM(CASE WHEN f.sub_code IN ('EXP0240', 'EXP0250')   THEN f.total_000s ELSE 0 END) AS depreciation,
        SUM(CASE WHEN f.sub_code = 'EXP0390'                 THEN f.total_000s ELSE 0 END) AS total_cost
    FROM nhs_silver.fct_tac f
    CROSS JOIN yrs y
    WHERE f.financial_year IN (y.first_year, y.latest_year)
      AND f.sub_code IN ('SCI0100A', 'SCI0110A', 'EXP0130', 'EXP0170',
                         'EXP0260', 'EXP0240', 'EXP0250', 'EXP0390')
    GROUP BY f.financial_year
),
delta AS (
    SELECT
        MAX(CASE WHEN l.financial_year = y.first_year THEN l.income - l.total_cost END)  AS start_result,
        SUM(CASE WHEN l.financial_year = y.latest_year THEN 1 ELSE -1 END * l.income)       AS d_income,
        SUM(CASE WHEN l.financial_year = y.latest_year THEN 1 ELSE -1 END * l.staff)        AS d_staff,
        SUM(CASE WHEN l.financial_year = y.latest_year THEN 1 ELSE -1 END * l.drugs)        AS d_drugs,
        SUM(CASE WHEN l.financial_year = y.latest_year THEN 1 ELSE -1 END * l.impairments)  AS d_impairments,
        SUM(CASE WHEN l.financial_year = y.latest_year THEN 1 ELSE -1 END * l.depreciation) AS d_depreciation,
        SUM(CASE WHEN l.financial_year = y.latest_year THEN 1 ELSE -1 END * l.total_cost)   AS d_total_cost,
        MAX(CASE WHEN l.financial_year = y.latest_year THEN l.income - l.total_cost END) AS end_result
    FROM year_lines l
    CROSS JOIN yrs y
)
SELECT 1 AS step, CONCAT('Operating result ', (SELECT first_year FROM yrs)) AS bridge_step,
       ROUND(start_result / 1000, 1) AS amount_m FROM delta
UNION ALL SELECT 2, 'Income growth',                     ROUND( d_income / 1000, 1)       FROM delta
UNION ALL SELECT 3, 'Staff cost growth',                 ROUND(-d_staff / 1000, 1)        FROM delta
UNION ALL SELECT 4, 'Drugs cost growth',                 ROUND(-d_drugs / 1000, 1)        FROM delta
UNION ALL SELECT 5, 'Impairments growth (non-cash)',     ROUND(-d_impairments / 1000, 1)  FROM delta
UNION ALL SELECT 6, 'Depreciation and amortisation',     ROUND(-d_depreciation / 1000, 1) FROM delta
UNION ALL SELECT 7, 'All other operating costs',
       ROUND(-(d_total_cost - d_staff - d_drugs - d_impairments - d_depreciation) / 1000, 1)  FROM delta
UNION ALL SELECT 8, CONCAT('Operating result ', (SELECT latest_year FROM yrs)),
       ROUND(end_result / 1000, 1) FROM delta
ORDER BY step;


-- name: expense_line_growth
-- Every TAC08 operating-expense line, ranked by its increase between the first
-- and latest year, with its share of the total cost increase.
-- Technique: join the fact table to the SubCode dimension for labels, pivot two
-- years, then SUM() OVER () for each line's share of the whole and RANK().
WITH yrs AS (
    SELECT MIN(financial_year) AS first_year, MAX(financial_year) AS latest_year
    FROM nhs_silver.fct_tac
),
by_line AS (
    SELECT
        sc.description                                                            AS line_item,
        sc.analytics_category,
        SUM(CASE WHEN f.financial_year = y.first_year  THEN f.total_000s ELSE 0 END) AS first_000s,
        SUM(CASE WHEN f.financial_year = y.latest_year THEN f.total_000s ELSE 0 END) AS latest_000s
    FROM nhs_silver.fct_tac f
    JOIN nhs_silver.dim_subcode sc ON sc.sub_code = f.sub_code
    CROSS JOIN yrs y
    WHERE f.worksheet_name = 'TAC08 Op Exp'
      AND sc.is_subtotal = 0
      AND f.financial_year IN (y.first_year, y.latest_year)
    GROUP BY sc.description, sc.analytics_category
)
SELECT
    RANK() OVER (ORDER BY latest_000s - first_000s DESC)                                    AS growth_rank,
    line_item,
    analytics_category,
    ROUND(latest_000s / 1000, 1)                                                            AS latest_m,
    ROUND((latest_000s - first_000s) / 1000, 1)                                             AS increase_m,
    ROUND(100 * (latest_000s / NULLIF(first_000s, 0) - 1), 1)                               AS growth_pct,
    ROUND(100 * (latest_000s - first_000s) / SUM(latest_000s - first_000s) OVER (), 1)      AS share_of_cost_increase_pct
FROM by_line
ORDER BY growth_rank
LIMIT 12;


-- name: pay_share_by_sector
-- Pay as a share of income for the median trust in each sector, every year, and
-- the change on the year before.
-- Technique: median via ROW_NUMBER() and COUNT() OVER, then LAG() on the result,
-- two layers of window functions over two CTEs.
WITH ranked AS (
    SELECT
        sector,
        financial_year,
        pay_pct_income,
        ROW_NUMBER() OVER (PARTITION BY sector, financial_year ORDER BY pay_pct_income) AS rn,
        COUNT(*)     OVER (PARTITION BY sector, financial_year)                         AS n
    FROM v_kpis
    WHERE pay_pct_income IS NOT NULL
),
medians AS (
    SELECT sector, financial_year,
           AVG(CASE WHEN rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)) THEN pay_pct_income END) AS median_pay_pct
    FROM ranked
    GROUP BY sector, financial_year
)
SELECT
    sector,
    financial_year,
    ROUND(median_pay_pct, 1)                                                       AS median_pay_pct,
    ROUND(median_pay_pct - LAG(median_pay_pct) OVER (PARTITION BY sector ORDER BY financial_year), 1)
                                                                                   AS change_pts
FROM medians
ORDER BY sector, financial_year;


-- name: wte_data_quality
-- Why cost per WTE is not used: trusts whose reported whole-time-equivalent
-- staff (TAC09) cannot support their pay bill. Each trust's pay per WTE is
-- compared with its sector median; more than three times the median is flagged.
-- Technique: a median per group as a CTE, joined back to the detail rows, with
-- a ratio test as the anomaly rule.
WITH base AS (
    SELECT org_code, organisation_name, sector, financial_year,
           pay_000s, total_wte, pay_000s / NULLIF(total_wte, 0) AS pay_per_wte_000s
    FROM v_kpis
    WHERE total_wte > 0
),
ranked AS (
    SELECT b.*,
           ROW_NUMBER() OVER (PARTITION BY sector, financial_year ORDER BY pay_per_wte_000s) AS rn,
           COUNT(*)     OVER (PARTITION BY sector, financial_year)                           AS n
    FROM base b
),
medians AS (
    SELECT sector, financial_year,
           AVG(CASE WHEN rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)) THEN pay_per_wte_000s END) AS median_pay_per_wte
    FROM ranked
    GROUP BY sector, financial_year
)
SELECT
    b.financial_year,
    b.sector,
    b.organisation_name,
    ROUND(b.pay_000s / 1000, 1)                         AS pay_m,
    ROUND(b.total_wte, 0)                               AS reported_wte,
    ROUND(b.pay_per_wte_000s, 1)                        AS pay_per_wte_000s,
    ROUND(b.pay_per_wte_000s / m.median_pay_per_wte, 1) AS times_sector_median
FROM base b
JOIN medians m ON m.sector = b.sector AND m.financial_year = b.financial_year
WHERE b.pay_per_wte_000s > 3 * m.median_pay_per_wte
ORDER BY b.financial_year, times_sector_median DESC;
