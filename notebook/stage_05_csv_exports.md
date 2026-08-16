# Stage ⑤ — CSV Exports

> `data/processed/powerbi_export/` — populated by `python/reporting/export_for_powerbi.py`, which
> queries the views and tables from [stage ④](stage_04_mysql_analytics.md) — connecting to `nhs_gold`,
> fully-qualifying `nhs_silver.dim_trust`/`nhs_silver.dim_subcode` for the joins that need them — and
> writes eleven CSVs in roughly 30 seconds. This stage's only job is portability: turn a live database
> dependency into flat files any tool — Power BI, a reviewer with no MySQL access — can consume.

---

## One Helper, Ten Callers

Every export funnels through a single function:

```python
def export_query(engine, sql: str, filename: str, **params) -> int:
    df = pd.read_sql(text(sql), engine.connect(), params=params if params else None)
    out_path = OUT_DIR / filename
    df.to_csv(out_path, index=False, encoding="utf-8-sig")  # utf-8-sig for Excel compat
    log.info("  Exported %d rows → %s", len(df), filename)
    return len(df)
```

`main()` just calls ten `export_*(engine)` functions in sequence — `export_dimensions` (writes both
`dim_trust.csv` and `dim_financial_year.csv` in one call), `export_ie_summary`,
`export_expenditure_breakdown`, `export_workforce`, `export_kpis`, `export_income_detail`,
`export_expenditure_detail`, `export_profit_and_loss`, `export_balance_sheet`,
`export_sector_benchmarks` — eleven files total. No orchestration logic beyond that: each function owns
one SQL query and one output file.

---

## Two Details That Shape Every File

**The UTF-8 BOM.** `encoding="utf-8-sig"` on every `to_csv()` call prepends a byte-order mark. Without it,
Excel — and Power BI's CSV connector, which shares Excel's parser on Windows — misreads the `£` symbol in
column values. This bit me once during testing; it's now non-negotiable on every export in this file.

**`CAST(... AS SIGNED)` in the SQL itself**, on every `_000s` column, rather than trusting pandas to
coerce MySQL's native `DECIMAL`:

```sql
SELECT
    org_code, organisation_name, sector, region, trust_type, financial_year,
    CAST(patient_care_income_000s AS SIGNED) AS patient_care_income_000s,
    CAST(total_income_000s AS SIGNED)         AS total_income_000s,
    CAST(operating_surplus_000s AS SIGNED)    AS operating_surplus_000s,
    CAST(net_surplus_000s AS SIGNED)          AS net_surplus_000s
FROM v_income_expenditure
ORDER BY financial_year, org_code
```

Reading an unwrapped `DECIMAL(14,0)` column back into pandas produces Python `Decimal` objects, which
write to CSV with inconsistent formatting. Casting to a signed integer in SQL guarantees plain numbers in
the file, every time.

---

## Two Files That Don't Come From a View

`export_income_detail()` and `export_expenditure_detail()` are the only two exports that query `fct_tac`
directly instead of a pre-aggregated `v_*` view — because a drilldown-by-line-item table is exactly the
one shape none of the summary views produce (including `v_profit_and_loss`/`v_balance_sheet`, which are
one row per trust per year, not one row per line item):

```sql
SELECT
    t.org_code, t.organisation_name, t.sector, t.trust_type,
    f.financial_year, f.sub_code,
    sc.description AS line_item, sc.analytics_category,
    CAST(f.total_000s AS SIGNED) AS amount_000s
FROM fct_tac f
JOIN dim_trust   t  ON f.org_code = t.org_code
JOIN dim_subcode sc ON f.sub_code = sc.sub_code
WHERE f.worksheet_name IN ('TAC06 Op Inc 1', 'TAC07 Op Inc 2')   -- income; TAC08 for expenditure
  AND f.main_code NOT LIKE '%PY%'
  AND sc.is_subtotal = 0                                         -- excludes summary rows
ORDER BY f.financial_year, t.org_code, f.sub_code
```

`sc.is_subtotal = 0` matters here specifically: without it, a Power BI visual summing this file would
double-count every trust's total alongside its own line items.

## One File That Breaks the £000s Convention on Purpose

`export_sector_benchmarks()` pre-aggregates `v_kpis` by `(financial_year, sector, trust_type)` in SQL —
counts, sums, and averages across every trust in a sector — and divides its money columns by 1,000 in the
query itself, so the CSV lands in **£millions**, not £000s:

```sql
ROUND(SUM(total_income_000s) / 1000, 0) AS total_income_m,
```

This is the one deliberate exception to the £000s rule established back in [stage ①](stage_01_nhs_england_source.md):
sector-level sums in £000s run to eight figures and stop being readable on a benchmarking chart axis.

---

## The Eleven Files

| File | Source | Grain |
|------|--------|-------|
| `dim_trust.csv` | `nhs_silver.dim_trust` table | One row per trust (215) |
| `dim_financial_year.csv` | `nhs_silver.dim_financial_year` table | One row per financial year (5) |
| `ie_summary.csv` | `v_income_expenditure` | One row per trust per year |
| `expenditure_breakdown.csv` | `v_expenditure_breakdown` | One row per trust per year |
| `workforce.csv` | `v_workforce` | One row per trust per year |
| `kpis.csv` | `v_kpis` | One row per trust per year |
| `income_detail.csv` | `nhs_silver.fct_tac` + `dim_subcode`, filtered | One row per trust per year per income SubCode |
| `expenditure_detail.csv` | `nhs_silver.fct_tac` + `dim_subcode`, filtered | One row per trust per year per expenditure SubCode |
| `profit_and_loss.csv` | `v_profit_and_loss` | One row per trust per year — full statutory P&L, ~27 lines pivoted into columns |
| `balance_sheet.csv` | `v_balance_sheet` | One row per trust per year — full statutory Balance Sheet, 40 `BAL*` lines pivoted into columns |
| `sector_benchmarks.csv` | `v_kpis`, aggregated | One row per financial year per sector per trust type |

Full column-by-column schema for each file is in `PROJECT_DOCUMENTATION.md`, stage ⑤.

---

## Stage ⑤ Summary

| Concept | Design Decision | Why |
|---------|------------------|-----|
| One `export_query()` helper | Every export funnels through it | One place to get encoding/logging right, once |
| `utf-8-sig` on every file | BOM-prefixed UTF-8 | Excel/Power BI's CSV connector misreads `£` without it |
| `CAST(... AS SIGNED)` on every `_000s` column | Done in SQL, not pandas | Avoids `Decimal`-object formatting noise in the CSV |
| Two detail exports query `fct_tac` directly | No summary view produces line-item grain | `is_subtotal = 0` prevents double-counting on import |
| `sector_benchmarks.csv` is in £m, not £000s | Divided by 1,000 in the SQL | Sector-level £000s sums are unreadable on a chart axis |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [python/reporting/export_for_powerbi.py](../python/reporting/export_for_powerbi.py) | Full script — `export_query()` plus all ten `export_*()` functions |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md), stage ⑤ | The narrative version, plus the full per-file column schema and the Power BI model diagram |

---

*Previous: [Stage ④ — MySQL Analytics](stage_04_mysql_analytics.md)*
*Next: [Stage ⑥ — Power BI Dashboard](stage_06_powerbi_dashboard.md)*
