# NHS Trust Financial Analytics

> **The NHS sector moved from a £1.6bn surplus in 2021/22 to a £1.6bn deficit in 2023/24 — a £3.2bn swing in two years.**
> This project builds an end-to-end analytics pipeline to surface that story from raw NHS England public data.

---

## What this project is

An end-to-end financial analytics pipeline using **real NHS England Trust Accounts Consolidation (TAC) data**, covering **206 NHS Trusts and Foundation Trusts** across **three financial years (2021/22 – 2023/24)**.

It models the work of an NHS Trust finance analytics function: ingesting annual accounts data, computing sector KPIs against NHS FReM conventions, and producing board-ready outputs in Power BI.

**Why it exists:** NHS England already publishes this data — it just doesn't publish it in usable form. TAC data is released as six separate Excel workbooks a year, in a long/narrow SubCode format designed for archival completeness, not analysis. There is no consolidated, multi-year, trust-level view anywhere in the public data as published. Building one means combining six files across three years, resolving inconsistent formats between them, and pivoting a SubCode taxonomy that isn't self-explanatory without a data dictionary — and the numbers it surfaces describe a sector in genuine distress (see [Key findings](#key-findings) below).

**Objectives:**

1. Ingest and consolidate three years of published TAC data — six workbooks, 206 NHS organisations — into a single, queryable data warehouse
2. Build a reusable, idempotent pipeline that can absorb a new year's data without manual rework or risk of duplication
3. Compute the core NHS financial KPIs against NHS England's own published RAG thresholds, not an invented scoring system
4. Keep the data model auditable — every figure traceable back to the exact source file, TAC schedule, and SubCode it came from
5. Deliver the result as an interactive dashboard usable by a non-technical audience — a finance director or board — not just query output for another analyst

Full technical documentation, including the full business case, methodology, and stage-by-stage build notes: [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md)

---

## The six-stage pipeline

Data moves in one direction only — source to dashboard — with each stage owned by a different technology:

<p align="center">
<img src="docs/images/pipeline_architecture.png" width="480" alt="Six-stage pipeline architecture: NHS England source files are manually downloaded into data/raw/, ingested by load_tac_data.py into MySQL staging (nhs_bronze), joined and upserted into MySQL analytics (nhs_silver) as a star schema, pivoted by SQL views into nhs_gold, exported by export_for_powerbi.py to CSV, and imported into the Power BI dashboard." />
</p>

| Stage | What it does |
|-------|--------------|
| ① NHS England (source) | NHS England's annual TAC publication — audited Trust accounts, consolidated and published as public data |
| ② Raw Excel files | Six workbooks (~170MB) downloaded manually into `data/raw/` — a fixed, reproducible snapshot |
| ③ MySQL staging (`nhs_bronze`) | `load_tac_data.py` lands the data close to verbatim — minimal transformation, full auditability |
| ④ MySQL analytics (`nhs_silver` → `nhs_gold`) | Staging data resolved to ODS codes and upserted into a star schema (`nhs_silver`); SQL views in `nhs_gold` pivot SubCodes into KPI-ready and full statutory P&L/Balance Sheet tables |
| ⑤ CSV exports | `export_for_powerbi.py` writes 11 flat CSVs — portable, no database connection required |
| ⑥ Power BI dashboard | 5-page interactive report — the only stage a non-technical end user actually interacts with |

Full detail on each stage — including the schema, SQL, and design rationale — is in [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md).

---

## Key findings

| Metric | 2021/22 | 2022/23 | 2023/24 |
|--------|---------|---------|---------|
| Total NHS income | £110.3bn | £118.4bn | £129.2bn |
| Total NHS expenditure | £108.7bn | £118.2bn | £130.8bn |
| Sector operating surplus / (deficit) | **+£1.6bn** | +£148m | **−£1.6bn** |
| Trusts in deficit | 37 of 211 | 85 of 207 | **124 of 206** |
| Average EBITDA margin | 4.6% | 4.3% | 3.6% |

**The headline:** Pay inflation following the 2023 Agenda for Change uplift, combined with clinical supply cost pressures, drove expenditure growth of 10.7% in 2023/24 against income growth of 9.1%. More than half of all NHS Trusts ended 2023/24 in deficit — the worst collective financial position since NHS provider finance reporting began in its current form.

---

## NHS domain coverage

This project applies real NHS finance conventions throughout:

| Convention | Implementation |
|-----------|----------------|
| NHS Financial Reporting Manual (FReM) | IFRS-aligned chart of accounts, SoCI structure |
| TAC worksheet mapping | TAC02 (I&E) · TAC08 (expenditure) · TAC09 (workforce) |
| NHS period labels | M01 (April) → M12 (March); financial year not calendar year |
| ODS organisation codes | 3-character provider codes (`org_code`) across all dimensions |
| Agenda for Change pay context | Pay as % of income KPI; WTE cost benchmarking |
| EBITDA margin RAG thresholds | ≥5% Green · 2–5% Amber · <2% Red (NHS England standard) |
| Financial year labelling | `YYYY/YY` (e.g. `2023/24`); no calendar-month grain — TAC is an annual return |

---

## Technical skills demonstrated

| Skill | Implementation |
|-------|---------------|
| Data engineering | Python pipeline ingesting 6 NHS Excel TAC files (~170MB) into MySQL |
| Dimensional modelling | Star schema: `dim_trust` · `dim_financial_year` · `dim_worksheet` · `dim_subcode` → `fct_tac` (2.18M rows) |
| SQL analytics | Analytical views for I&E, expenditure, workforce, KPIs, and sector scorecard |
| Data quality | 10-query validation suite with expected-value assertions |
| Financial KPIs | EBITDA margin · Pay % of income · Cost per WTE · Net surplus margin |
| Power BI | 11-CSV export pipeline · 51 DAX measures · 5-page dashboard |
| NHS domain knowledge | TAC subcode taxonomy · FReM conventions · sector benchmarks |

---

## Database schema

Three MySQL databases, medallion-style:

**`nhs_bronze`** — raw landing layer

| Table | Description |
|-------|-------------|
| `stg_tac_raw` | Raw ingest from all 6 TAC Excel files |
| `stg_provider_list` | ODS provider reference |

**`nhs_silver`** — conformed layer

| Table | Rows | Description |
|---|---|---|
| `dim_trust` | 215 | Provider master — ODS code, sector, region, trust type |
| `fct_tac` | 2,179,740 | Fact table: one row per org / year / subcode / data type |
| `dim_subcode` | ~1,000 | SubCode → label reference, all 28 real TAC worksheets |

**`nhs_gold`** — curated analytical views, referencing `nhs_silver.*` tables

| View | Rows | Description |
|---|---|---|
| `v_income_expenditure` | 624 | I&E summary per trust per year (SoCI — TAC02) |
| `v_profit_and_loss` | 624 | Full statutory P&L — every real TAC02 SoCI/SOC line |
| `v_expenditure_breakdown` | 624 | Pay / non-pay / drugs / depreciation split (TAC08) |
| `v_workforce` | 624 | Staff costs and WTE (TAC09) |
| `v_balance_sheet` | 624 | Full statutory Balance Sheet — all 40 TAC03 SoFP `BAL*` lines |
| `v_kpis` | 624 | Computed KPIs with RAG status |
| `v_trust_annual_scorecard` | 624 | Wide view combining all metrics |

---

## Project structure

```text
portfolio-01-nhs-trust-financial-analytics/
│
├── README.md                          ← Quick-start summary
├── PROJECT_DOCUMENTATION.md           ← Full technical documentation
├── CLAUDE.md                          ← AI coding assistant instructions; real architecture reference
│
├── agent_docs/                        ← Domain knowledge reference (see note under stage ④ re: scope)
│   ├── data_dictionary.md             ← TAC columns and SubCode reference
│   ├── kpi_definitions.md             ← KPI formulas and RAG thresholds
│   └── report_calendar.md             ← NHS period table and reporting cycle
│
├── data/                              ← git-ignored; regenerated by the pipeline, not committed
│   ├── raw/                           ← Source NHS Excel files — stage ②
│   │   ├── TAC_NHS_trusts_2021-22.xlsx
│   │   ├── TAC_NHS_foundation_trusts_2021-22.xlsx
│   │   ├── TAC_NHS_trusts_2022-23.xlsx
│   │   ├── TAC_NHS_foundation_trusts_2022-23.xlsx
│   │   ├── TAC_NHS_trusts_2023-24.xlsx
│   │   └── TAC_NHS_foundation_trusts_2023-24.xlsx
│   └── processed/
│       ├── validation_report.csv      ← Output of validate_tac_data.py — stage ④
│       └── powerbi_export/            ← Eleven CSV files for Power BI — stage ⑤
│           ├── dim_trust.csv
│           ├── dim_financial_year.csv
│           ├── ie_summary.csv
│           ├── expenditure_breakdown.csv
│           ├── workforce.csv
│           ├── kpis.csv
│           ├── income_detail.csv
│           ├── expenditure_detail.csv
│           ├── profit_and_loss.csv
│           ├── balance_sheet.csv
│           └── sector_benchmarks.csv
│
├── docs/
│   └── images/                        ← Screenshots and diagrams embedded in PROJECT_DOCUMENTATION.md
│       ├── pipeline_architecture.png
│       ├── mysql_client_server.png
│       ├── star_schema.png
│       └── powerbi_model.png
│
├── python/
│   ├── CLAUDE.md                      ← Python layer coding standards
│   ├── ingestion/
│   │   ├── load_tac_data.py           ← Main ingestion script — stages ③④
│   │   └── build_subcode_reference.py ← One-off dim_subcode label generator (not in the daily pipeline)
│   ├── transformation/                ← Enrichment and validation — stage ④
│   │   ├── transform_tac_data.py
│   │   └── validate_tac_data.py
│   └── reporting/
│       └── export_for_powerbi.py      ← CSV export script — stage ⑤
│
├── sql/
│   ├── CLAUDE.md                      ← SQL layer coding standards
│   ├── schema/
│   │   ├── create_tables_mysql.sql    ← Full schema: staging + dims + fact + views — stages ③④
│   │   └── create_tables.sql          ← PostgreSQL equivalent (reference)
│   ├── views/                         ← Standalone, canonical version of each v_* view — stage ④
│   │   ├── v_income_expenditure.sql
│   │   ├── v_profit_and_loss.sql
│   │   ├── v_expenditure_breakdown.sql
│   │   ├── v_workforce.sql
│   │   ├── v_balance_sheet.sql
│   │   ├── v_kpis.sql
│   │   ├── v_trust_annual_scorecard.sql
│   │   └── v_validation_checks.sql    ← 10 data quality checks with expected values
│   └── analysis/                      ← Standalone, presentation-ready analytical queries
│       ├── sector_trend_analysis.sql
│       └── benchmarking_analysis.sql
│
├── power_bi/
│   ├── CLAUDE.md                      ← Power BI coding standards
│   ├── setup_guide.md                 ← Model relationships, DAX, page specs — stage ⑥
│   ├── dax_measures.md                ← All 51 measures, human-readable — stage ⑥
│   └── dax/
│       └── _Measures.tmdl             ← Exact createOrReplace export from Power BI Desktop
│
├── reports/
│   ├── CLAUDE.md                      ← Report narrative standards (FReM)
│   └── nhs_sector_financial_review_2324.md ← Annual sector outturn narrative built on this data
│
└── notebook/                           ← Stage-by-stage build notes kept while developing the pipeline
    ├── stage_01_nhs_england_source.md
    ├── stage_02_raw_excel_files.md
    ├── stage_03_mysql_staging.md
    ├── stage_04_mysql_analytics.md
    ├── stage_05_csv_exports.md
    └── stage_06_powerbi_dashboard.md
```

---

## Power BI outputs

| File | Rows | Purpose |
|------|------|---------|
| `dim_trust.csv` | 215 | Trust slicer — sector, region, trust type |
| `dim_financial_year.csv` | 5 | Year slicer |
| `kpis.csv` | 624 | KPI scorecards and scatter plots |
| `ie_summary.csv` | 624 | I&E waterfall and trend lines |
| `expenditure_breakdown.csv` | 624 | Pay vs non-pay breakdown |
| `workforce.csv` | 624 | WTE and staff cost analysis |
| `income_detail.csv` | 9,144 | Income drilldown by TAC line item |
| `expenditure_detail.csv` | 11,856 | Cost drilldown by TAC line item |
| `profit_and_loss.csv` | ~624 | Full statutory P&L — every real TAC02 SoCI/SOC line |
| `balance_sheet.csv` | ~624 | Full statutory Balance Sheet — all 40 TAC03 SoFP lines |
| `sector_benchmarks.csv` | 30 | Aggregated sector benchmarks |

---

## Reproduce from scratch

**Prerequisites:** Python 3.11+ · MySQL 8.0+ · NHS TAC Excel files in `data/raw/`

```bash
# 1. Create schema and seed dimensions
#    Run sql/schema/create_tables_mysql.sql in MySQL Workbench or DbVisualizer

# 2. Ingest all 6 NHS TAC files (~10 minutes)
python python/ingestion/load_tac_data.py

# 3. Validate the load
#    Run sql/views/v_validation_checks.sql — 10 queries with expected values

# 4. Export for Power BI
python python/reporting/export_for_powerbi.py
#    Writes 11 CSVs to data/processed/powerbi_export/

# 5. Build the dashboard
#    Follow power_bi/setup_guide.md
```

**Python dependencies:** `pandas` · `sqlalchemy` · `pymysql` · `openpyxl`

---

## Data notes

- Source: [NHS England TAC publications](https://www.england.nhs.uk/financial-accounting-reporting-systems/nhs-england-finance-returns-publications-guidance/trust-accounts-consolidation-tac/) — publicly available, updated annually
- Each annual file includes Prior Year (PY) rows; the pipeline retains Current Year (CY) only to prevent double-counting
- Total WTE (`STA0410`) is the reliable workforce metric; WTE by staff group has subcode ambiguity in the TAC format
- 2021/22 source files use slightly different column naming (`Organisation Name` with space; `Value number`) — handled in the ingestion layer

---

*For full technical documentation, NHS background, data model detail, and analytical narrative: [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md)*
