# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

An end-to-end financial analytics pipeline built on **real NHS England Trust Accounts Consolidation (TAC)
data**: 6 Excel source files → MySQL → SQL analytical views → CSV export for Power BI. It covers 206 NHS
Trusts/Foundation Trusts across financial years 2021/22–2023/24. See [README.md](README.md) for headline
findings and [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md) for the full domain/data walkthrough
(NHS background, TAC file format, KPI methodology, glossary).

## Architecture (read this before touching the pipeline)

**Two-database MySQL pattern**, built by `sql/schema/create_tables_mysql.sql`:

- `nhs_stg` — staging: `stg_tac_raw` (raw rows from the "All data" sheet), `stg_provider_list` (trust
  name → ODS code lookup from the "List of Providers" sheet). Reloaded per file with DELETE+INSERT, so
  reruns are idempotent.
- `nhs_finance` — analytics: dims `dim_trust`, `dim_financial_year`, `dim_worksheet`, `dim_subcode`; one
  fact table `fct_tac`; five `v_*` analytical views.

**The fact table is long/narrow (EAV-style), not wide.** `fct_tac` has one row per
`(org_code, financial_year, main_code, sub_code)` — e.g. one row for "patient care income", another for
"total pay costs", etc. — because that's the shape NHS England publishes TAC data in. There is no
pre-pivoted income-statement table. Getting a trust's income/expenditure requires pivoting on `sub_code`
(e.g. `SCI0100A` = patient care income, `SCI0140A` = operating surplus, `EXP0130` = staff costs) — this is
exactly what the SQL views do. See `agent_docs/data_dictionary.md` for the SubCode reference and
`PROJECT_DOCUMENTATION.md`, stage ④, for the full star-schema diagram.

**Pipeline flow** (each stage reads what the last stage wrote — run them in order):

```
data/raw/*.xlsx  →  python/ingestion/load_tac_data.py       →  nhs_stg.* , nhs_finance.dim_trust / fct_tac
                 →  sql/views/*.sql (or create_tables_mysql.sql)  →  nhs_finance.v_*
                 →  python/transformation/transform_tac_data.py   →  data/processed/*.csv (enrichment/benchmarks)
                 →  python/transformation/validate_tac_data.py    →  data/processed/validation_report.csv
                 →  python/reporting/export_for_powerbi.py        →  data/processed/powerbi_export/*.csv
```

Each Excel file drives one `financial_year` × `trust_type` (`NHS_TRUST` or `FOUNDATION_TRUST`) load. Each
annual file contains both Current Year (CY) and Prior Year (PY) rows for comparison — the ingestion layer
keeps **CY only** (`main_code` filtered on `year_type`) to avoid double-counting across years.

**View layer** (`nhs_finance.v_*`, defined in both `sql/schema/create_tables_mysql.sql` and standalone
under `sql/views/` — the standalone files are the fuller/canonical versions, check both if a view looks
out of date):

- `v_income_expenditure` — pivots TAC02 SoCI SubCodes into I&E per trust/year
- `v_expenditure_breakdown` — pivots TAC08 into pay/non-pay/depreciation/drugs/clinical-negligence
- `v_workforce` — pivots TAC09 into staff costs and WTE
- `v_kpis` — joins the three views above and computes EBITDA margin, pay % of income, cost per WTE, net
  surplus margin, plus RAG flags
- `v_trust_annual_scorecard` — wide view combining everything, built for DirectQuery and ad-hoc SQL; used by
  `transform_tac_data.py`, `validate_tac_data.py`, and `sql/analysis/*.sql`. **Not** what
  `export_for_powerbi.py` queries — the CSV export reads the four views above separately instead

### agent_docs/ and subdirectory CLAUDE.md files describe a broader, partly-aspirational model — don't take them at face value

`agent_docs/kpi_definitions.md` and the per-folder `python/CLAUDE.md` / `sql/CLAUDE.md` /
`power_bi/CLAUDE.md` files were written against a more general finance-analytics schema (PostgreSQL,
monthly `period_key`/`period_label` M01–M12, a `fct_income_expenditure` fact table with
`account_type`/`data_type`/`budget_000s` vs `actual_000s`, a `fct_workforce` fact with staff groups and
contract types, `icb_code` on `dim_trust`) — **none of that is what's implemented**. The actual pipeline
is MySQL, annual-only (no period/month grain — TAC is an annual return), actuals-only (no budget/forecast
data exists), and uses the EAV `fct_tac` design above. Concretely:

- `dim_trust.trust_type` is `NHS_TRUST` | `FOUNDATION_TRUST` — not the `ACUTE`/`MENTAL_HEALTH`/etc. values
  the trust *sector* takes. Sector (`Acute`, `Mental Health`, `Community`, `Ambulance`, `Specialist`)
  lives in `dim_trust.sector`, sourced from NHS England's own labels.
- There is no `icb_code`, no `period_key`, no `data_type`, no `subjective_code`, no CIP/budget/capital
  data anywhere in the schema or source files.
- Of the 6 core KPIs listed below, only 4 are implemented in `v_kpis` (EBITDA margin, pay % of income,
  cost per WTE, net surplus margin). CIP Achievement %, Budget Variance %, and Capital Spend % of Plan are
  explicitly out of scope — `sql/views/v_kpis.sql`'s header comment says why (they need data sources —
  CIP tracker, in-year budget returns, ERIC estates — that aren't part of this project).

Trust the code (`sql/schema/`, `sql/views/`, `python/`) over `agent_docs/` or the subfolder CLAUDE.md
files when they disagree.

## Commands

No test suite, linter, or `requirements.txt` exists in this repo yet — don't assume `pytest`/`ruff` are
configured. `python/CLAUDE.md` references a `python/tests/` layout and `utils/db.py`; neither exists.

```bash
# Dependencies (no requirements.txt — install directly)
pip install pandas sqlalchemy pymysql openpyxl

# 1. Build schema (databases, tables, seed dimensions, views) — run the whole file in a MySQL client
mysql -u root -p < sql/schema/create_tables_mysql.sql

# 2. Ingest all 6 TAC files found in data/raw/ (~10-15 min)
python python/ingestion/load_tac_data.py

# 3. Validate the load — writes data/processed/validation_report.csv
python python/transformation/validate_tac_data.py
# or run the ad-hoc checks directly:
mysql -u root -p nhs_finance < sql/views/v_validation_checks.sql

# 4. Enrichment/benchmarking transforms
python python/transformation/transform_tac_data.py

# 5. Export CSVs for Power BI → data/processed/powerbi_export/
python python/reporting/export_for_powerbi.py
```

DB connection settings (`DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`) are hardcoded at the top of each
`python/**/*.py` script (`root` / local MySQL on `127.0.0.1:3306`) rather than read from environment —
this contradicts `python/CLAUDE.md`'s "never hardcode credentials" rule but is the current reality; update
the constants in each script if your local MySQL differs.

`data/raw/` (source Excel, ~170MB) and `data/processed/` (generated) are git-ignored — regenerate rather
than expecting them to be present after a fresh clone.

## NHS domain conventions

- Financial year: 1 April–31 March, labelled `YYYY/YY` (e.g. `2023/24`). Filter by `financial_year`, never
  calendar month.
- Currency: all monetary columns are **£000s**; suffix them `_000s`. Never mix £000s and £m in one
  table/visual. In narrative report text (`reports/`), spell out thousands/millions instead of using
  `_000s` notation.
- Org identifiers: `org_code` is the 3-character ODS code (e.g. `R1H` = Barts Health NHS Trust).
- `data/raw/` — source files from NHS England, do not modify. `data/processed/` — pipeline output, always
  regenerable.

## Naming conventions

| Layer       | Convention        | Example                |
|-------------|-------------------|-------------------------|
| SQL table   | `snake_case`      | `stg_provider_finance` |
| SQL view    | `v_` prefix       | `v_income_expenditure` |
| Python fn   | `snake_case`      | `promote_to_fact()`    |
| DAX measure | PascalCase + `[]` | `[EBITDA Margin %]`    |
| File        | `snake_case`      | `load_tac_data.py`     |

## Do not

- Do not hardcode trust ODS codes in queries or scripts — parameterise.
- Do not commit `data/raw/` or `data/processed/` (already git-ignored).
- Do not use calendar-year grouping — always `financial_year`.
- Do not present forecast/plan figures as actuals in `reports/` output — this dataset is actuals-only, so
  any forecast/budget figure is necessarily sourced from outside this pipeline and must be labelled.
