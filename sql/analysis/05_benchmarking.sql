-- =============================================================================
-- 05_benchmarking.sql
-- Board question: which kinds of trust do better, and which trusts stand out
-- from comparable peers?
--
-- Replaces the older benchmarking_analysis.sql. No query names a year, and no
-- threshold is typed in: size bands and pay outliers are computed from the
-- data. Cost per WTE and other WTE-based measures are left out, because the
-- TAC09 staff numbers are incomplete for some trusts (see wte_data_quality in
-- 02_cost_drivers.sql).
-- All money is £000s in the data; columns ending _m are converted for reading.
-- =============================================================================

USE nhs_gold;


-- name: size_quartile_kpis
-- Trusts split into four equal-sized groups by income in the latest year, with
-- the actual income range of each group and its performance. Small trusts
-- should be compared with small trusts.
-- Technique: NTILE(4) for the bands, with the band labels built from each
-- band's own MIN and MAX rather than typed-in boundaries.
WITH banded AS (
    SELECT
        total_income_000s, operating_surplus_000s, ebitda_000s, pay_000s,
        NTILE(4) OVER (ORDER BY total_income_000s) AS size_quartile
    FROM v_kpis
    WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
)
SELECT
    size_quartile,
    CONCAT('£', ROUND(MIN(total_income_000s) / 1000), 'm to £',
           ROUND(MAX(total_income_000s) / 1000), 'm')              AS income_range,
    COUNT(*)                                                       AS trusts,
    ROUND(100 * SUM(operating_surplus_000s) / SUM(total_income_000s), 2) AS operating_margin_pct,
    ROUND(100 * SUM(ebitda_000s) / SUM(total_income_000s), 2)     AS ebitda_margin_pct,
    ROUND(100 * SUM(pay_000s) / SUM(total_income_000s), 1)        AS pay_pct_income,
    SUM(operating_surplus_000s < 0)                                AS trusts_in_deficit,
    ROUND(100 * AVG(operating_surplus_000s < 0), 1)                AS pct_in_deficit
FROM banded
GROUP BY size_quartile
ORDER BY size_quartile;


-- name: foundation_vs_nhs_trust
-- Foundation trusts have more financial freedom than NHS trusts. Do they
-- perform better? Both types side by side each year, with the gap.
-- Technique: pivot the two trust types into columns with conditional
-- aggregation, so the comparison and the gap sit on one row per year.
SELECT
    financial_year,
    SUM(trust_type = 'FOUNDATION_TRUST')                                         AS foundation_trusts,
    SUM(trust_type = 'NHS_TRUST')                                                AS nhs_trusts,
    ROUND(100 * SUM(IF(trust_type = 'FOUNDATION_TRUST', ebitda_000s, 0))
              / SUM(IF(trust_type = 'FOUNDATION_TRUST', total_income_000s, 0)), 2) AS ft_ebitda_margin_pct,
    ROUND(100 * SUM(IF(trust_type = 'NHS_TRUST', ebitda_000s, 0))
              / SUM(IF(trust_type = 'NHS_TRUST', total_income_000s, 0)), 2)        AS nhs_trust_ebitda_margin_pct,
    ROUND(100 * AVG(IF(trust_type = 'FOUNDATION_TRUST', operating_surplus_000s < 0, NULL)), 1)
                                                                                  AS ft_pct_in_deficit,
    ROUND(100 * AVG(IF(trust_type = 'NHS_TRUST', operating_surplus_000s < 0, NULL)), 1)
                                                                                  AS nhs_trust_pct_in_deficit
FROM v_kpis
GROUP BY financial_year
ORDER BY financial_year;


-- name: pay_outliers_latest_year
-- Trusts in the top quarter of their own sector for pay as a share of income
-- in the latest year, ordered by how far they sit above the sector median.
-- "High" is defined by each sector's own distribution, so a mental health trust
-- (where pay is naturally a larger share) is not judged against acute trusts.
-- Technique: PERCENT_RANK() within each sector for the cut-off, a ROW_NUMBER()
-- median per sector, both from the same CTE.
WITH latest AS (
    SELECT organisation_name, sector, region, pay_pct_income, ebitda_margin_pct
    FROM v_kpis
    WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
      AND pay_pct_income IS NOT NULL
),
ranked AS (
    SELECT
        l.*,
        PERCENT_RANK() OVER (PARTITION BY sector ORDER BY pay_pct_income) AS pct_rank,
        ROW_NUMBER()   OVER (PARTITION BY sector ORDER BY pay_pct_income) AS rn,
        COUNT(*)       OVER (PARTITION BY sector)                         AS n
    FROM latest l
),
medians AS (
    SELECT sector, AVG(CASE WHEN rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)) THEN pay_pct_income END) AS median_pay_pct
    FROM ranked
    GROUP BY sector
)
SELECT
    r.sector,
    r.organisation_name,
    r.region,
    r.pay_pct_income,
    ROUND(m.median_pay_pct, 1)                       AS sector_median_pay_pct,
    ROUND(r.pay_pct_income - m.median_pay_pct, 1)    AS above_median_pts,
    ROUND(100 * r.pct_rank)                          AS percentile_in_sector,
    r.ebitda_margin_pct
FROM ranked r
JOIN medians m ON m.sector = r.sector
WHERE r.pct_rank >= 0.75
ORDER BY above_median_pts DESC
LIMIT 25;


-- name: regional_health_latest_year
-- Which of the seven NHS England regions are under the most financial strain
-- in the latest year?
-- Technique: weighted margins per region, ranked with RANK() on the share of
-- trusts in deficit.
SELECT
    RANK() OVER (ORDER BY AVG(operating_surplus_000s < 0) DESC)          AS strain_rank,
    region,
    COUNT(*)                                                             AS trusts,
    ROUND(SUM(total_income_000s) / 1000, 1)                              AS income_m,
    ROUND(SUM(operating_surplus_000s) / 1000, 1)                         AS operating_surplus_m,
    ROUND(100 * SUM(operating_surplus_000s) / SUM(total_income_000s), 2) AS operating_margin_pct,
    ROUND(100 * SUM(ebitda_000s) / SUM(total_income_000s), 2)            AS ebitda_margin_pct,
    SUM(operating_surplus_000s < 0)                                      AS trusts_in_deficit,
    ROUND(100 * AVG(operating_surplus_000s < 0), 1)                      AS pct_in_deficit
FROM v_kpis
WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
  AND region IS NOT NULL
GROUP BY region
ORDER BY strain_rank;


-- name: ebitda_movers
-- The ten trusts whose EBITDA margin improved most, and the ten whose margin
-- worsened most, between the last two years.
-- Technique: LAG() for the change, then two ROW_NUMBER() orderings (best and
-- worst) over the same rows, kept with a single WHERE.
WITH changes AS (
    SELECT
        organisation_name, sector, financial_year,
        ebitda_margin_pct,
        LAG(ebitda_margin_pct) OVER (PARTITION BY org_code ORDER BY financial_year) AS prior_ebitda_margin_pct
    FROM v_kpis
),
ranked AS (
    SELECT
        c.*,
        ebitda_margin_pct - prior_ebitda_margin_pct                                             AS change_pts,
        ROW_NUMBER() OVER (ORDER BY ebitda_margin_pct - prior_ebitda_margin_pct DESC)          AS best_rank,
        ROW_NUMBER() OVER (ORDER BY ebitda_margin_pct - prior_ebitda_margin_pct ASC)           AS worst_rank
    FROM changes c
    WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
      AND prior_ebitda_margin_pct IS NOT NULL
)
SELECT
    IF(best_rank <= 10, 'Most improved', 'Most worsened')   AS movement,
    organisation_name,
    sector,
    prior_ebitda_margin_pct,
    ebitda_margin_pct,
    ROUND(change_pts, 1)                                    AS change_pts
FROM ranked
WHERE best_rank <= 10 OR worst_rank <= 10
ORDER BY change_pts DESC;


-- name: private_patient_income_latest_year
-- The fifteen trusts earning most from private patients in the latest year,
-- and what share of their income it is. Private work is one lever a trust
-- can pull to improve its finances.
-- Technique: one income line (INC0330) pulled out of the long fact table and
-- joined to the KPI view, top N with RANK().
WITH private_income AS (
    SELECT org_code, total_000s AS private_000s
    FROM nhs_silver.fct_tac
    WHERE worksheet_name = 'TAC06 Op Inc 1'
      AND sub_code = 'INC0330'              -- Private patient income
      AND financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
      AND total_000s > 0
)
SELECT
    RANK() OVER (ORDER BY p.private_000s DESC)                      AS income_rank,
    k.organisation_name,
    k.sector,
    k.region,
    ROUND(p.private_000s / 1000, 1)                                 AS private_patient_income_m,
    ROUND(100 * p.private_000s / k.total_income_000s, 2)            AS pct_of_income,
    k.ebitda_margin_pct
FROM private_income p
JOIN v_kpis k
  ON k.org_code = p.org_code
 AND k.financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
ORDER BY income_rank
LIMIT 15;


-- name: academic_income_and_margin
-- Does research and education income go with stronger finances? Trusts are
-- grouped into quartiles by the share of income from research and
-- development (INC1230A) and education and training (INC1240A), and each
-- group's margins are compared.
-- Technique: two SubCodes pivoted from the fact table, joined to the view,
-- NTILE(4) on the derived share, then weighted margins per quartile.
WITH academic AS (
    SELECT
        org_code,
        SUM(CASE WHEN sub_code = 'INC1230A' THEN total_000s ELSE 0 END) AS research_000s,
        SUM(CASE WHEN sub_code = 'INC1240A' THEN total_000s ELSE 0 END) AS education_000s
    FROM nhs_silver.fct_tac
    WHERE worksheet_name = 'TAC07 Op Inc 2'
      AND sub_code IN ('INC1230A', 'INC1240A')
      AND financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
    GROUP BY org_code
),
banded AS (
    SELECT
        k.total_income_000s, k.operating_surplus_000s, k.ebitda_000s,
        COALESCE(a.research_000s, 0) + COALESCE(a.education_000s, 0)                      AS academic_000s,
        NTILE(4) OVER (ORDER BY (COALESCE(a.research_000s, 0) + COALESCE(a.education_000s, 0))
                                / k.total_income_000s)                                  AS academic_quartile
    FROM v_kpis k
    LEFT JOIN academic a ON a.org_code = k.org_code
    WHERE k.financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
)
SELECT
    academic_quartile,
    COUNT(*)                                                              AS trusts,
    ROUND(100 * MIN(academic_000s / total_income_000s), 1)               AS min_academic_share_pct,
    ROUND(100 * MAX(academic_000s / total_income_000s), 1)               AS max_academic_share_pct,
    ROUND(100 * SUM(operating_surplus_000s) / SUM(total_income_000s), 2) AS operating_margin_pct,
    ROUND(100 * SUM(ebitda_000s) / SUM(total_income_000s), 2)            AS ebitda_margin_pct,
    ROUND(100 * AVG(operating_surplus_000s < 0), 1)                      AS pct_in_deficit
FROM banded
GROUP BY academic_quartile
ORDER BY academic_quartile;
