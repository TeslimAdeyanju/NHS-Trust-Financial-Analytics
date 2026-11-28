-- =============================================================================
-- 04_sector_trends.sql
-- Board question: how have NHS trust finances moved over time, nationally, by
-- sector and by region?
--
-- Replaces the older sector_trend_analysis.sql. No query names a year: the year
-- range comes from the data. Margins are income-weighted (SUM / SUM), so a
-- £2bn trust counts for more than a £50m one; where a simple average across
-- trusts is shown, the column says so.
-- All money is £000s in the data; columns ending _m or _bn are converted.
--
-- Each query starts with a "-- name:" line (used by analysis/nhs_analysis.py);
-- the file also runs top to bottom:  mysql nhs_gold < sql/analysis/04_sector_trends.sql
-- =============================================================================

USE nhs_gold;


-- name: national_trend
-- The national picture each year: income, costs, results and margins, with
-- income growth on the year before.
-- Technique: aggregate per year in a CTE, then LAG() for growth; an
-- income-weighted margin next to the simple average across trusts, which
-- shows how much large trusts pull the national figure.
WITH yearly AS (
    SELECT
        financial_year,
        COUNT(*)                     AS trusts,
        SUM(operating_surplus_000s < 0) AS trusts_in_deficit,
        SUM(total_income_000s)       AS income_000s,
        SUM(total_expenditure_000s)  AS expenditure_000s,
        SUM(operating_surplus_000s)  AS operating_surplus_000s,
        SUM(net_surplus_000s)        AS net_surplus_000s,
        SUM(ebitda_000s)             AS ebitda_000s,
        AVG(ebitda_margin_pct)       AS mean_trust_ebitda_pct
    FROM v_kpis
    GROUP BY financial_year
)
SELECT
    financial_year,
    trusts,
    trusts_in_deficit,
    ROUND(income_000s / 1e6, 2)                                              AS income_bn,
    ROUND(100 * (income_000s / LAG(income_000s) OVER (ORDER BY financial_year) - 1), 1)
                                                                             AS income_growth_pct,
    ROUND(expenditure_000s / 1e6, 2)                                         AS expenditure_bn,
    ROUND(operating_surplus_000s / 1000, 1)                                  AS operating_surplus_m,
    ROUND(net_surplus_000s / 1000, 1)                                        AS net_surplus_m,
    ROUND(100 * ebitda_000s / income_000s, 2)                                AS weighted_ebitda_margin_pct,
    ROUND(mean_trust_ebitda_pct, 2)                                          AS mean_trust_ebitda_margin_pct
FROM yearly
ORDER BY financial_year;


-- name: sector_kpis_latest_year
-- Each sector in the latest year, split by NHS trust and foundation trust, with
-- a subtotal per sector and a national total.
-- Technique: GROUP BY sector, trust_type WITH ROLLUP; GROUPING() labels the
-- subtotal and total rows; the deficit of deficit trusts only, by conditional SUM.
SELECT
    IF(GROUPING(sector) = 1, 'All sectors', sector)                         AS sector,
    IF(GROUPING(trust_type) = 1, 'All', trust_type)                         AS trust_type,
    COUNT(*)                                                                AS trusts,
    ROUND(SUM(total_income_000s) / 1000, 1)                                 AS income_m,
    ROUND(100 * SUM(ebitda_000s) / SUM(total_income_000s), 2)              AS ebitda_margin_pct,
    ROUND(100 * SUM(pay_000s) / SUM(total_income_000s), 1)                 AS pay_pct_income,
    ROUND(100 * SUM(net_surplus_000s) / SUM(total_income_000s), 2)         AS net_margin_pct,
    SUM(operating_surplus_000s < 0)                                         AS trusts_in_deficit,
    ROUND(SUM(CASE WHEN operating_surplus_000s < 0
                   THEN operating_surplus_000s ELSE 0 END) / 1000, 1)       AS deficit_of_deficit_trusts_m
FROM v_kpis
WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
GROUP BY sector, trust_type WITH ROLLUP
ORDER BY GROUPING(sector), sector, GROUPING(trust_type), trust_type;


-- name: regional_income_growth
-- Income growth in each NHS England region between the first and latest year,
-- ranked.
-- Technique: a one-row CTE holding the year range, a two-year pivot with
-- conditional aggregation, then RANK() on the growth.
WITH yrs AS (
    SELECT MIN(financial_year) AS first_year, MAX(financial_year) AS latest_year
    FROM nhs_silver.fct_tac
),
pivoted AS (
    SELECT
        k.region,
        SUM(CASE WHEN k.financial_year = y.first_year  THEN k.total_income_000s END) AS income_first,
        SUM(CASE WHEN k.financial_year = y.latest_year THEN k.total_income_000s END) AS income_latest,
        SUM(CASE WHEN k.financial_year = y.first_year  THEN k.operating_surplus_000s END) AS result_first,
        SUM(CASE WHEN k.financial_year = y.latest_year THEN k.operating_surplus_000s END) AS result_latest
    FROM v_kpis k
    CROSS JOIN yrs y
    WHERE k.region IS NOT NULL
    GROUP BY k.region
)
SELECT
    RANK() OVER (ORDER BY income_latest / income_first DESC)     AS growth_rank,
    region,
    ROUND(income_first / 1000, 1)                                AS income_first_year_m,
    ROUND(income_latest / 1000, 1)                               AS income_latest_year_m,
    ROUND(100 * (income_latest / income_first - 1), 1)           AS income_growth_pct,
    ROUND((result_latest - result_first) / 1000, 1)              AS change_in_operating_result_m
FROM pivoted
ORDER BY growth_rank;


-- name: ebitda_rag_by_sector
-- How many trusts in each sector fall in each EBITDA band in the latest year,
-- using the same Green / Amber / Red bands as v_kpis (>= 5%, 2-5%, < 2%).
-- Technique: pivot a categorical column (ebitda_rag) into one column per value,
-- reusing the view's own banding rather than re-typing the thresholds.
SELECT
    sector,
    COUNT(*)                                                        AS trusts,
    SUM(ebitda_rag = 'Green')                                       AS green_5pct_plus,
    SUM(ebitda_rag = 'Amber')                                       AS amber_2_to_5pct,
    SUM(ebitda_rag = 'Red')                                         AS red_below_2pct,
    SUM(ebitda_rag = 'Not assessed')                                AS not_assessed,
    ROUND(100 * AVG(ebitda_rag = 'Red'), 1)                         AS pct_red
FROM v_kpis
WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
GROUP BY sector
ORDER BY pct_red DESC;


-- name: income_concentration_latest_year
-- The twenty largest trusts by income in the latest year, each one's share of
-- national income, and the running share: how concentrated NHS trust income is.
-- Technique: SUM() OVER () for the national total, a running SUM() OVER
-- (ORDER BY ...) for the cumulative share, and DENSE_RANK().
WITH latest AS (
    SELECT organisation_name, sector, total_income_000s, operating_surplus_000s, ebitda_margin_pct
    FROM v_kpis
    WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
),
shares AS (
    SELECT
        l.*,
        DENSE_RANK() OVER (ORDER BY total_income_000s DESC)                          AS income_rank,
        100 * total_income_000s / SUM(total_income_000s) OVER ()                     AS share_pct,
        100 * SUM(total_income_000s) OVER (ORDER BY total_income_000s DESC
                                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            / SUM(total_income_000s) OVER ()                                         AS cumulative_share_pct
    FROM latest l
)
SELECT
    income_rank,
    organisation_name,
    sector,
    ROUND(total_income_000s / 1000, 1)       AS income_m,
    ROUND(share_pct, 2)                      AS share_of_national_pct,
    ROUND(cumulative_share_pct, 1)           AS cumulative_share_pct,
    ROUND(operating_surplus_000s / 1000, 1)  AS operating_surplus_m,
    ebitda_margin_pct
FROM shares
WHERE income_rank <= 20
ORDER BY income_rank;


-- name: worst_net_margins_latest_year
-- The twenty trusts with the lowest net surplus margin in the latest year, and
-- whether each one is getting worse: its margin the year before alongside.
-- Technique: LAG() computed over every year first, then filtered to the latest
-- year (filtering first would leave LAG nothing to look back at).
WITH margins AS (
    SELECT
        organisation_name, sector, trust_type, financial_year,
        total_income_000s, net_surplus_000s, net_surplus_margin_pct, ebitda_margin_pct,
        LAG(net_surplus_margin_pct) OVER (PARTITION BY org_code ORDER BY financial_year) AS prior_net_margin_pct
    FROM v_kpis
)
SELECT
    RANK() OVER (ORDER BY net_surplus_margin_pct)                AS worst_rank,
    organisation_name,
    sector,
    trust_type,
    ROUND(total_income_000s / 1000, 1)                           AS income_m,
    ROUND(net_surplus_000s / 1000, 1)                            AS net_surplus_m,
    net_surplus_margin_pct,
    prior_net_margin_pct,
    ROUND(net_surplus_margin_pct - prior_net_margin_pct, 1)     AS change_pts,
    ebitda_margin_pct
FROM margins
WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
ORDER BY worst_rank
LIMIT 20;


-- name: drugs_and_negligence_trend
-- Two cost lines outside a trust's direct control: drugs, and the clinical
-- negligence premium paid to NHS Resolution, as a share of income by sector
-- and year, with the year-on-year movement.
-- Technique: weighted shares per group, then LAG() over each sector's years
-- for two measures in the same window.
WITH sector_year AS (
    SELECT
        sector,
        financial_year,
        SUM(drugs_cost_000s)          AS drugs_000s,
        SUM(clinical_negligence_000s) AS negligence_000s,
        SUM(total_income_000s)        AS income_000s
    FROM v_kpis
    GROUP BY sector, financial_year
)
SELECT
    sector,
    financial_year,
    ROUND(drugs_000s / 1000, 1)                                         AS drugs_m,
    ROUND(100 * drugs_000s / income_000s, 2)                            AS drugs_pct_income,
    ROUND(100 * (drugs_000s / LAG(drugs_000s) OVER w - 1), 1)           AS drugs_growth_pct,
    ROUND(negligence_000s / 1000, 1)                                    AS negligence_m,
    ROUND(100 * negligence_000s / income_000s, 2)                       AS negligence_pct_income,
    ROUND(100 * (negligence_000s / LAG(negligence_000s) OVER w - 1), 1) AS negligence_growth_pct
FROM sector_year
WINDOW w AS (PARTITION BY sector ORDER BY financial_year)
ORDER BY sector, financial_year;


-- name: net_finance_costs
-- What trusts pay to finance themselves each year: interest received, interest
-- paid, and the public dividend capital (PDC) dividend paid to government.
-- These lines sit below the operating result in the SoCI, which stores costs
-- as negative values, so the net cost is the plain sum of the three.
-- Technique: pivot three SubCodes out of the long fact table in one pass.
SELECT
    financial_year,
    ROUND(SUM(CASE WHEN sub_code = 'SCI0150' THEN total_000s ELSE 0 END) / 1000, 1) AS finance_income_m,
    ROUND(SUM(CASE WHEN sub_code = 'SCI0160' THEN total_000s ELSE 0 END) / 1000, 1) AS finance_expense_m,
    ROUND(SUM(CASE WHEN sub_code = 'SCI0170' THEN total_000s ELSE 0 END) / 1000, 1) AS pdc_dividend_m,
    ROUND(SUM(total_000s) / 1000, 1)                                                 AS net_finance_cost_m,
    COUNT(DISTINCT org_code)                                                         AS trusts_reporting
FROM nhs_silver.fct_tac
WHERE worksheet_name = 'TAC02 SoCI'
  AND sub_code IN ('SCI0150', 'SCI0160', 'SCI0170')
GROUP BY financial_year
ORDER BY financial_year;
