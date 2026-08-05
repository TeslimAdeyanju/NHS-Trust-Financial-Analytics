# Stage ⑥ — Power BI Dashboard

> Imports the nine CSVs from [stage ⑤](stage_05_csv_exports.md) (or connects directly to
> [stage ④](stage_04_mysql_analytics.md) via DirectQuery), builds the model relationships and DAX
> measures below, and renders five report pages. This is the only stage a non-technical end user — a
> finance director, a board — actually interacts with; there is no code to run here, only a model to
> build inside Power BI Desktop, which is why this stage's "code" lives in `.md`/`.tmdl` files rather
> than a script.

---

## Import and Rename

Each CSV is imported via **Get Data → Text/CSV** and renamed on import to the `fact_`/`dim_` prefix
convention Power BI's own model view then displays:

| CSV | Imported as |
|-----|---------------|
| `dim_trust.csv` | `dim_trust` |
| `dim_financial_year.csv` | `dim_financial_year` |
| `ie_summary.csv` | `fact_ie_summary` |
| `expenditure_breakdown.csv` | `fact_expenditure_breakdown` |
| `workforce.csv` | `fact_workforce` |
| `kpis.csv` | `fact_kpis` |
| `income_detail.csv` | `fact_income_detail` |
| `expenditure_detail.csv` | `fact_expenditure_detail` |
| `sector_benchmarks.csv` | `fact_sector_benchmarks` |

Plus one table that isn't a CSV at all: **`_Measures`**, created via *Enter Data → blank table*, holding
none of the data — only DAX measures, so they have a home not tied to any one fact table.

---

## Model Relationships

Every fact table joins to the two dimensions on `org_code` and/or `financial_year`, single-direction,
many-to-one — with one deliberate exception:

```text
fact_ie_summary[org_code / financial_year]              → dim_trust / dim_financial_year
fact_expenditure_breakdown[org_code / financial_year]    → dim_trust / dim_financial_year
fact_workforce[org_code / financial_year]                → dim_trust / dim_financial_year
fact_kpis[org_code / financial_year]                     → dim_trust / dim_financial_year
fact_income_detail[org_code / financial_year]            → dim_trust / dim_financial_year
fact_expenditure_detail[org_code / financial_year]       → dim_trust / dim_financial_year
fact_sector_benchmarks[financial_year]                   → dim_financial_year   (no dim_trust — see below)
```

`fact_sector_benchmarks` has no relationship to `dim_trust`: it was built pre-aggregated by
`(sector, trust_type)` in [stage ⑤](stage_05_csv_exports.md)'s SQL, so it has no `org_code` column to join
on — `sector` and `trust_type` stay unmodelled attributes on the table itself. Full seven-fact star
diagram, re-exported from Power BI's own model view, is in `PROJECT_DOCUMENTATION.md`, stage ⑤.

---

## DAX Measures — 51 in One Table

Every measure — all 51 — lives in `_Measures`, never inside a fact table, and never as an implicit
measure dragged straight off a column. Three real patterns cover almost all of them:

```dax
-- £000s → £m conversion (every base financial measure)
Total Income (£m) =
DIVIDE(SUMX(fact_ie_summary, fact_ie_summary[total_income_000s]), 1000, 0)

-- Ratio / percentage measure
EBITDA Margin % =
DIVIDE(
    SUMX(fact_kpis, fact_kpis[ebitda_000s]),
    SUMX(fact_kpis, fact_kpis[total_income_000s]),
    BLANK()
) * 100

-- Year-on-year: resolve the prior year via a lookup SWITCH, then re-evaluate a base measure against it
Prior Year =
VAR _current = SELECTEDVALUE(dim_financial_year[financial_year])
RETURN SWITCH(_current, "2023/24", "2022/23", "2022/23", "2021/22", "2021/22", "2020/21", BLANK())

Prior Year Income (£m) =
VAR _py = [Prior Year]
RETURN IF(NOT ISBLANK(_py), CALCULATE([Total Income (£m)], dim_financial_year[financial_year] = _py), BLANK())
```

RAG status measures return a string (`"Green"` / `"Amber"` / `"Red"` / `"Grey"`), and a matching
`... RAG Colour` measure maps that string to a verified hex code for conditional formatting:

```dax
EBITDA RAG =
VAR _margin = [EBITDA Margin %]
RETURN SWITCH(TRUE(), ISBLANK(_margin), "Grey", _margin >= 5, "Green", _margin >= 2, "Amber", "Red")

EBITDA RAG Colour =
SWITCH([EBITDA RAG], "Green", "#009639", "Amber", "#FFB81C", "Red", "#DA291C", "#E8EDEE")
```

The 51 measures split into seven families: Core I&E, KPIs, Workforce, Year-on-Year, RAG Status, Sector
Benchmark, and Dynamic Titles/Labels (slicer-aware page titles like `Page Title - I&E`, built with
`SELECTEDVALUE(..., "All Years")` so a page title updates live as filters change).

Two versions of every measure exist, and only one is authoritative if they ever disagree:

- **`power_bi/dax_measures.md`** — human-readable, grouped by family, meant to be read
- **`power_bi/dax/_Measures.tmdl`** — the exact `createOrReplace` export from Power BI Desktop's TMDL
  view, including format strings and lineage tags — **this file wins** on any disagreement

---

## Report Pages

| Page | Purpose |
|------|---------|
| Executive Summary | KPI cards, sector breakdown, deficit/surplus donut, 3-year trend lines |
| Income & Expenditure | Waterfall bridge, trust-level matrix, scatter plots |
| Expenditure Detail | Pay vs non-pay breakdown, drugs costs, clinical negligence trend |
| Benchmarking | EBITDA distribution, top/bottom performers, peer comparison table |
| Workforce | WTE trends, cost per WTE, staff cost as % of income |

`dim_trust[sector]`, `dim_trust[region]`, and `dim_financial_year[financial_year]` are placed as slicers
on every page, filtering all of that page's visuals simultaneously.

## The RAG Palette

Read directly out of the `*RAG Colour` measures, not approximated — these four values are the only ones
used for anything tied to a RAG status:

```text
Green (sustainable): #009639     Amber (at risk): #FFB81C
Red (unsustainable):  #DA291C     Grey (no data):  #E8EDEE
```

---

## Stage ⑥ Summary

| Concept | Design Decision | Why |
|---------|------------------|-----|
| `_Measures` as a blank table | Not a data table — holds only measures | Measures don't belong to one fact table any more than a KPI does |
| `fact_`/`dim_` rename on import | Matches SQL and DAX naming | One convention across the whole stack, not just inside MySQL |
| `fact_sector_benchmarks` has no `dim_trust` relationship | It's pre-aggregated by sector in SQL | There's no `org_code` column left to join on |
| `.tmdl` wins over `.md` on disagreement | `.tmdl` is a machine export, `.md` is hand-maintained | The hand-maintained copy is the one that can drift |
| RAG colours read from DAX, not approximated | Four fixed hex values | Consistency across every visual using RAG status |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [power_bi/setup_guide.md](../power_bi/setup_guide.md) | Full import steps, relationship list, page-by-page visual specs |
| [power_bi/dax_measures.md](../power_bi/dax_measures.md) | All 51 measures, grouped by family, human-readable |
| [power_bi/dax/_Measures.tmdl](../power_bi/dax/_Measures.tmdl) | The authoritative, machine-exported measure definitions |
| [power_bi/CLAUDE.md](../power_bi/CLAUDE.md) | Naming conventions, standard measure patterns, visual standards |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md), stage ⑥ | The narrative version |

---

*Previous: [Stage ⑤ — CSV Exports](stage_05_csv_exports.md)*
