-- =============================================================================
-- 03_peer_benchmarking.sql
-- Board question: how does one trust compare with its peers?
--
-- The trust is a parameter, never typed into a query. Set it before running:
--     SET @org_code = 'RXX';      -- any ODS code
-- If @org_code is not set, the first block picks the trust with the lowest
-- operating margin in the latest year, so the file always has an example.
-- All money is £000s in the data; columns ending _m are converted for reading.
-- =============================================================================

USE nhs_gold;


-- name: choose_trust
-- Technique: a session variable as the query parameter, defaulted with COALESCE
-- and a subquery when the caller has not set it. A variable set in the client
-- takes the connection's collation, which can differ from the tables'
-- (utf8mb4_unicode_ci); converting it once here stops "Illegal mix of
-- collations" errors in every later comparison with org_code.
SET @org_code = CONVERT(COALESCE(
    @org_code,
    (SELECT org_code
     FROM v_kpis
     WHERE financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
     ORDER BY operating_surplus_000s / NULLIF(total_income_000s, 0)
     LIMIT 1)
) USING utf8mb4) COLLATE utf8mb4_unicode_ci;
SELECT org_code, organisation_name, sector, region, trust_type
FROM v_kpis
WHERE org_code = @org_code
  AND financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac);


-- name: peer_position
-- Where the trust sits in its sector on five measures in the latest year.
-- percentile = 100 for the highest value in the sector, 0 for the lowest.
-- Technique: unpivot the measures to rows with UNION ALL, then PERCENT_RANK(),
-- a sector median and a quartile with NTILE(), all as window functions over
-- the same partition.
WITH latest AS (
    SELECT MAX(financial_year) AS financial_year FROM nhs_silver.fct_tac
),
peers AS (
    SELECT s.*
    FROM v_kpis s
    JOIN latest l ON l.financial_year = s.financial_year
    WHERE s.sector = (SELECT sector FROM nhs_silver.dim_trust WHERE org_code = @org_code)
),
measures AS (
    SELECT org_code, 1 AS ord, 'Operating margin %' AS measure,
           100 * operating_surplus_000s / NULLIF(total_income_000s, 0) AS value FROM peers
    UNION ALL SELECT org_code, 2, 'EBITDA margin %',       ebitda_margin_pct FROM peers
    UNION ALL SELECT org_code, 3, 'Pay as % of income',    pay_pct_income    FROM peers
    UNION ALL SELECT org_code, 4, 'Net surplus margin %',  net_surplus_margin_pct FROM peers
    UNION ALL SELECT org_code, 5, 'Income £m',             total_income_000s / 1000 FROM peers
),
ranked AS (
    SELECT
        org_code, ord, measure, value,
        PERCENT_RANK() OVER w                                           AS pct_rank,
        NTILE(4)       OVER w                                           AS quartile,
        ROW_NUMBER()   OVER w                                           AS rn,
        COUNT(*)       OVER (PARTITION BY measure)                      AS n
    FROM measures
    WHERE value IS NOT NULL
    WINDOW w AS (PARTITION BY measure ORDER BY value)
),
medians AS (
    SELECT measure, AVG(CASE WHEN rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)) THEN value END) AS sector_median
    FROM ranked
    GROUP BY measure
)
SELECT
    r.measure,
    ROUND(r.value, 1)              AS trust_value,
    ROUND(m.sector_median, 1)      AS sector_median,
    ROUND(r.value - m.sector_median, 1) AS difference,
    ROUND(100 * r.pct_rank, 0)     AS percentile,
    r.quartile                     AS quartile_1_low_4_high,
    r.n                            AS trusts_in_sector
FROM ranked r
JOIN medians m ON m.measure = r.measure
WHERE r.org_code = @org_code
ORDER BY r.ord;


-- name: nearest_peers
-- A fairer peer group than the whole sector: the five trusts in the same sector
-- closest in size (income) to the selected trust, and how they performed.
-- Technique: a CTE self-joined so every peer row carries the selected trust's
-- income, ROW_NUMBER() ordered by the distance between the two, and the selected
-- trust kept in the output (distance 0) for comparison.
WITH sector_latest AS (
    SELECT s.org_code, s.organisation_name, s.total_income_000s, s.operating_surplus_000s,
           s.ebitda_margin_pct, s.pay_pct_income
    FROM v_kpis s
    WHERE s.financial_year = (SELECT MAX(financial_year) FROM nhs_silver.fct_tac)
      AND s.sector = (SELECT sector FROM nhs_silver.dim_trust WHERE org_code = @org_code)
),
candidates AS (
    SELECT
        p.*,
        ROW_NUMBER() OVER (ORDER BY ABS(p.total_income_000s - t.total_income_000s)) - 1 AS distance_rank
    FROM sector_latest p
    JOIN sector_latest t ON t.org_code = @org_code
)
SELECT
    IF(org_code = @org_code, 'Selected trust', CONCAT('Peer ', distance_rank)) AS role,
    organisation_name,
    ROUND(total_income_000s / 1000, 1)                                          AS income_m,
    ROUND(100 * operating_surplus_000s / NULLIF(total_income_000s, 0), 1)       AS operating_margin_pct,
    ebitda_margin_pct,
    pay_pct_income
FROM candidates
WHERE distance_rank <= 5
ORDER BY distance_rank;


-- name: trend_vs_sector
-- The trust against the median trust in its sector, every year, for operating
-- margin and pay as a share of income.
-- Technique: medians for every sector-year in one pass, a LEFT JOIN of the trust
-- onto its own sector, and LAG() for the trust's year-on-year change.
WITH base AS (
    SELECT org_code, sector, financial_year,
           100 * operating_surplus_000s / NULLIF(total_income_000s, 0) AS op_margin,
           pay_pct_income
    FROM v_kpis
),
ranked AS (
    SELECT sector, financial_year, op_margin, pay_pct_income,
           ROW_NUMBER() OVER (PARTITION BY sector, financial_year ORDER BY op_margin)      AS rn_m,
           ROW_NUMBER() OVER (PARTITION BY sector, financial_year ORDER BY pay_pct_income) AS rn_p,
           COUNT(*)     OVER (PARTITION BY sector, financial_year)                         AS n
    FROM base
),
medians AS (
    SELECT sector, financial_year,
           AVG(CASE WHEN rn_m IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)) THEN op_margin END)      AS median_op_margin,
           AVG(CASE WHEN rn_p IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)) THEN pay_pct_income END) AS median_pay_pct
    FROM ranked
    GROUP BY sector, financial_year
)
SELECT
    m.financial_year,
    ROUND(t.op_margin, 1)                                                AS trust_op_margin_pct,
    ROUND(m.median_op_margin, 1)                                         AS sector_median_op_margin_pct,
    ROUND(t.op_margin - LAG(t.op_margin) OVER (ORDER BY m.financial_year), 1) AS trust_change_pts,
    ROUND(t.pay_pct_income, 1)                                           AS trust_pay_pct,
    ROUND(m.median_pay_pct, 1)                                           AS sector_median_pay_pct
FROM medians m
JOIN base t
  ON t.sector = m.sector AND t.financial_year = m.financial_year AND t.org_code = @org_code
ORDER BY m.financial_year;


-- name: underlying_result
-- The trust's reported operating result next to its result before impairments,
-- every year. Impairments are pulled from the long fact table by SubCode.
-- Technique: pivot several SubCodes out of the EAV fact table in one pass with
-- conditional aggregation, then derive the underlying measures from them.
SELECT
    f.financial_year,
    ROUND(SUM(CASE WHEN f.sub_code IN ('SCI0100A', 'SCI0110A') THEN f.total_000s END) / 1000, 1) AS income_m,
    ROUND(SUM(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s END) / 1000, 1)               AS operating_result_m,
    ROUND(SUM(CASE WHEN f.sub_code = 'EXP0260'  THEN f.total_000s END) / 1000, 1)               AS impairments_m,
    ROUND((SUM(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s ELSE 0 END)
         + SUM(CASE WHEN f.sub_code = 'EXP0260'  THEN f.total_000s ELSE 0 END)) / 1000, 1)      AS result_before_impairments_m,
    ROUND(100 * (SUM(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s ELSE 0 END)
               + SUM(CASE WHEN f.sub_code = 'EXP0260'  THEN f.total_000s ELSE 0 END))
          / NULLIF(SUM(CASE WHEN f.sub_code IN ('SCI0100A', 'SCI0110A') THEN f.total_000s END), 0), 1)
                                                                                                  AS margin_before_impairments_pct
FROM nhs_silver.fct_tac f
WHERE f.org_code = @org_code
  AND f.sub_code IN ('SCI0100A', 'SCI0110A', 'SCI0140A', 'EXP0260')
GROUP BY f.financial_year
ORDER BY f.financial_year;
