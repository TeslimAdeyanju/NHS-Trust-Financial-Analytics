# Analysis: SQL answers to board questions

This folder answers the questions a trust board or finance director asks of the accounts, and the
answers are written in **SQL**. Each question has one query file in [`sql/analysis/`](../sql/analysis/)
and one notebook here that runs those queries against the MySQL warehouse and shows each query next to
its result. Python does no analysis: it runs the SQL and, once per notebook, draws a chart from a query
result.

| Question | SQL file | Notebook |
| --- | --- | --- |
| Where does the financial pressure sit, and is it getting worse? | [01_financial_pressure.sql](../sql/analysis/01_financial_pressure.sql) | [01 Financial pressure](notebooks/01_financial_pressure.ipynb) |
| Has income kept up with costs, and which cost lines grew fastest? | [02_cost_drivers.sql](../sql/analysis/02_cost_drivers.sql) | [02 Cost drivers](notebooks/02_cost_drivers.ipynb) |
| How does one trust compare with its peers? | [03_peer_benchmarking.sql](../sql/analysis/03_peer_benchmarking.sql) | [03 Peer benchmarking](notebooks/03_peer_benchmarking.ipynb) |
| How have finances moved, nationally, by sector and by region? | [04_sector_trends.sql](../sql/analysis/04_sector_trends.sql) | [04 Sector trends](notebooks/04_sector_trends.ipynb) |
| Which kinds of trust do better, and which stand out from peers? | [05_benchmarking.sql](../sql/analysis/05_benchmarking.sql) | [05 Benchmarking](notebooks/05_benchmarking.ipynb) |

## SQL techniques shown

| Technique | Where |
| --- | --- |
| Conditional aggregation and pivots (`SUM(CASE WHEN ...)`) | every file |
| `GROUP BY ... WITH ROLLUP` with `GROUPING()` labels, one and two levels | `deficit_share_by_sector`, `sector_kpis_latest_year` |
| Window functions: `LAG()`, `ROW_NUMBER()`, `RANK()`, `NTILE()`, `PERCENT_RANK()`, `SUM() OVER ()` | every file |
| Named windows (`WINDOW w AS (...)`) | `sector_result_trend`, `peer_position` |
| Median without a `MEDIAN()` function (`ROW_NUMBER()` + `COUNT() OVER`) | all three files |
| Top N per group, and best and worst N in one pass | `largest_deficits_with_impairments`, `ebitda_movers` |
| Running totals with an explicit window frame (`ROWS BETWEEN ...`) | `income_concentration_latest_year` |
| Window function over an aggregate (`RANK() OVER (ORDER BY AVG(...))`) | `regional_health_latest_year` |
| Bands computed from the data (`NTILE()` labelled by its own `MIN`/`MAX`; `PERCENT_RANK()` cut-offs per sector) | `size_quartile_kpis`, `pay_outliers_latest_year` |
| Income-weighted margins (`SUM / SUM`) against simple averages | `national_trend` |
| Year-on-year transitions with `LAG()` | `surplus_deficit_transitions` |
| Pivoting SubCodes out of the long (EAV) fact table | `surplus_bridge`, `underlying_result` |
| A profit bridge stacked with `UNION ALL` that reconciles exactly | `surplus_bridge` |
| Unpivoting measures to rows with `UNION ALL` | `peer_position` |
| CTE self-join for nearest-neighbour peer groups | `nearest_peers` |
| Session-variable parameters (`@org_code`) with a `COALESCE` default | `03_peer_benchmarking.sql` |
| Data-quality anomaly rule against a group median | `wte_data_quality` |

No query names a year or a trust. Years come from `MIN`/`MAX(financial_year)` in the data, and the trust is
the `@org_code` parameter, so the files keep working when a new year is loaded.

## How the queries are organised

Each query in a file starts with a `-- name:` line, followed by comments saying what it answers and which
technique it uses. That gives two ways to run them:

```bash
# Whole file, top to bottom, in any MySQL client
mysql -u root -p nhs_gold < sql/analysis/01_financial_pressure.sql

# One trust for the benchmarking file
mysql --commands -u root -p nhs_gold -e "SET @org_code = 'RGR'; SOURCE sql/analysis/03_peer_benchmarking.sql;"
```

In the notebooks, `nhs.sql(file, name)` (in [`nhs_analysis.py`](nhs_analysis.py)) reads the query with
that name from the file, runs it on one open connection (so `@org_code` persists between cells), displays
the SQL and returns the result.

Each query reads `v_kpis` at most once, and takes the year range from the indexed `nhs_silver.fct_tac`.
`v_trust_annual_scorecard` gives the same rows but rebuilds a join over the whole fact table every time it
is referenced, which made the queries several times slower.

## Run the notebooks

From the repository root, after the pipeline has loaded the warehouse:

```bash
pip install -r requirements.txt -r requirements-analysis.txt
export DB_PASSWORD='...'
jupyter nbconvert --to notebook --execute --inplace analysis/notebooks/*.ipynb
```

Notebook 03 benchmarks the trust in the `TRUST_ORG_CODE` environment variable (an ODS code). Without it,
the SQL defaults to the trust with the lowest operating margin in the latest year.

The notebooks are committed with their outputs so the queries and results show on GitHub. Re-run them
after every data load so the results never go stale.

## Reading the results

- **Annual, actuals only.** TAC is an annual return, so there is no monthly, budget or forecast analysis.
- **Operating surplus** is the SoCI line `SCI0140A` as each trust reported it. It includes impairments,
  which are non-cash write-downs of buildings and equipment. NHS England's own performance measure
  excludes them, so several queries show the result before impairments alongside. The reconciliation to
  NHS England's figures is in the [financial reconciliation workpaper](../reports/nhs_financial_reconciliation.md).
- **Cost per WTE is not used.** The `wte_data_quality` query shows why: the TAC09 staff numbers are
  incomplete for some trusts.
