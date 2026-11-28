-- =============================================================================
-- 01_financial_pressure.sql
-- Board question: where does the financial pressure sit, and is it getting worse?
--
-- Runs against nhs_gold (views) and nhs_silver (fact table). Every query derives
-- the years it needs from the data, so nothing here is pinned to one year.
-- All money is £000s in the data; columns ending _m are converted for reading.
--
-- Each query starts with a "-- name:" line. analysis/nhs_analysis.py uses that
-- marker to run one query at a time from the notebooks; the file also runs top
-- to bottom in any MySQL client:  mysql nhs_gold < sql/analysis/01_financial_pressure.sql
-- =============================================================================

USE nhs_gold;


-- name: deficit_share_by_sector
-- How many trusts in each sector reported an operating deficit, by year, with a
-- national total per year.
-- Technique: conditional aggregation, GROUP BY ... WITH ROLLUP for subtotals, and
-- GROUPING() to label the subtotal rows instead of leaving NULLs.
SELECT
    financial_year,
    IF(GROUPING(sector) = 1, 'All sectors', sector)            AS sector,
    COUNT(*)                                                    AS trusts,
    SUM(CASE WHEN operating_surplus_000s < 0 THEN 1 ELSE 0 END) AS trusts_in_deficit,
    ROUND(100 * AVG(operating_surplus_000s < 0), 1)             AS pct_in_deficit
FROM v_kpis
GROUP BY financial_year, sector WITH ROLLUP
HAVING GROUPING(financial_year) = 0
ORDER BY financial_year, GROUPING(sector), sector;


-- name: sector_result_trend
-- The combined operating result of each sector, and how far it moved from the
-- year before.
-- Technique: aggregate in a CTE, then LAG() over the sector's own years.
WITH sector_year AS (
    SELECT
        sector,
        financial_year,
        SUM(operating_surplus_000s) AS operating_surplus_000s,
        SUM(total_income_000s)      AS total_income_000s
    FROM v_kpis
    GROUP BY sector, financial_year
)
SELECT
    sector,
    financial_year,
    ROUND(operating_surplus_000s / 1000, 1)                                AS operating_surplus_m,
    ROUND(100 * operating_surplus_000s / NULLIF(total_income_000s, 0), 2)  AS operating_margin_pct,
    ROUND((operating_surplus_000s
           - LAG(operating_surplus_000s) OVER w) / 1000, 1)                AS change_on_prior_year_m
FROM sector_year
WINDOW w AS (PARTITION BY sector ORDER BY financial_year)
ORDER BY sector, financial_year;


-- name: margin_distribution_latest_year
-- The spread of operating margins inside each sector in the latest year: the
-- median trust, the worst and best, and how many sit below -5%.
-- Technique: MySQL has no MEDIAN(), so rank each trust with ROW_NUMBER() and
-- COUNT() OVER the sector, then average the one or two middle rows.
WITH latest AS (
    SELECT MAX(financial_year) AS financial_year FROM nhs_silver.fct_tac
),
ranked AS (
    SELECT
        s.sector,
        100 * s.operating_surplus_000s / NULLIF(s.total_income_000s, 0) AS margin_pct,
        ROW_NUMBER() OVER (PARTITION BY s.sector
                           ORDER BY s.operating_surplus_000s / NULLIF(s.total_income_000s, 0)) AS rn,
        COUNT(*)     OVER (PARTITION BY s.sector)                                              AS n
    FROM v_kpis s
    JOIN latest l ON l.financial_year = s.financial_year
)
SELECT
    sector,
    MAX(n)                                                                    AS trusts,
    ROUND(AVG(CASE WHEN rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2))
                   THEN margin_pct END), 2)                                   AS median_margin_pct,
    ROUND(MIN(margin_pct), 2)                                                 AS worst_margin_pct,
    ROUND(MAX(margin_pct), 2)                                                 AS best_margin_pct,
    SUM(margin_pct < -5)                                                      AS trusts_below_minus_5pct
FROM ranked
GROUP BY sector
ORDER BY median_margin_pct;


-- name: surplus_deficit_transitions
-- How trusts moved between surplus and deficit from one year to the next. A
-- board cares less about the count in deficit than about how many fell into it.
-- Technique: LAG() to put each trust's prior-year status on the same row, then
-- a pivot of the transitions with conditional aggregation.
WITH status AS (
    SELECT
        org_code,
        financial_year,
        IF(operating_surplus_000s < 0, 'Deficit', 'Surplus')  AS status_now,
        LAG(IF(operating_surplus_000s < 0, 'Deficit', 'Surplus'))
            OVER (PARTITION BY org_code ORDER BY financial_year) AS status_before,
        LAG(financial_year)
            OVER (PARTITION BY org_code ORDER BY financial_year) AS prior_year
    FROM v_kpis
)
SELECT
    CONCAT(prior_year, ' → ', financial_year)                                  AS period,
    SUM(status_before = 'Surplus' AND status_now = 'Surplus')                  AS stayed_in_surplus,
    SUM(status_before = 'Surplus' AND status_now = 'Deficit')                  AS fell_into_deficit,
    SUM(status_before = 'Deficit' AND status_now = 'Surplus')                  AS recovered_to_surplus,
    SUM(status_before = 'Deficit' AND status_now = 'Deficit')                  AS stayed_in_deficit
FROM status
WHERE status_before IS NOT NULL
GROUP BY prior_year, financial_year
ORDER BY financial_year;


-- name: largest_deficits_with_impairments
-- The three largest operating deficits in each sector in the latest year, with
-- the impairment charge pulled straight from the fact table. Impairments are
-- non-cash write-downs; adding them back gives the underlying result, which is
-- closer to how NHS England judges a trust's performance.
-- Technique: pivot one line out of the long (EAV) fact table, join it to the
-- view, and keep the top N per group with ROW_NUMBER().
WITH latest AS (
    SELECT MAX(financial_year) AS financial_year FROM nhs_silver.fct_tac
),
impairments AS (
    SELECT org_code, financial_year, SUM(total_000s) AS impairments_000s
    FROM nhs_silver.fct_tac
    WHERE worksheet_name = 'TAC08 Op Exp'
      AND sub_code = 'EXP0260'               -- Impairments net of reversals
    GROUP BY org_code, financial_year
),
ranked AS (
    SELECT
        s.sector,
        s.organisation_name,
        s.operating_surplus_000s,
        COALESCE(i.impairments_000s, 0)                                 AS impairments_000s,
        s.operating_surplus_000s + COALESCE(i.impairments_000s, 0)      AS underlying_surplus_000s,
        s.total_income_000s,
        ROW_NUMBER() OVER (PARTITION BY s.sector ORDER BY s.operating_surplus_000s) AS deficit_rank
    FROM v_kpis s
    JOIN latest l ON l.financial_year = s.financial_year
    LEFT JOIN impairments i
           ON i.org_code = s.org_code AND i.financial_year = s.financial_year
    WHERE s.operating_surplus_000s < 0
)
SELECT
    sector,
    deficit_rank,
    organisation_name,
    ROUND(operating_surplus_000s / 1000, 1)                                  AS operating_surplus_m,
    ROUND(impairments_000s / 1000, 1)                                        AS impairments_m,
    ROUND(underlying_surplus_000s / 1000, 1)                                 AS underlying_surplus_m,
    ROUND(100 * underlying_surplus_000s / NULLIF(total_income_000s, 0), 2)   AS underlying_margin_pct
FROM ranked
WHERE deficit_rank <= 3
ORDER BY sector, deficit_rank;
