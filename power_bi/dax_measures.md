# DAX Measures — NHS Finance Analytics Dashboard

All 51 measures live in a dedicated **`_Measures`** table (Enter Data → blank table → name `_Measures`) —
never inside a fact table. Follow the naming conventions in `power_bi/CLAUDE.md`: Title Case, `%` suffix
for percentages, `(£m)` suffix for millions, `(£000s)` suffix where values remain in thousands.

Table names below use the `fact_`/`dim_` prefixes Power BI's model view assigns once each CSV from
`data/processed/powerbi_export/` is imported as its own table — see `power_bi/setup_guide.md` for the full
import and relationship steps.

This file is the human-readable reference. The exact, machine-exported definition of every measure —
including format strings and lineage tags — lives at
[`power_bi/dax/_Measures.tmdl`](dax/_Measures.tmdl); if the two ever disagree, the `.tmdl` file is correct.

---

## Table of Contents

1. [Core I&E Measures](#1-core-ie-measures)
2. [KPI Measures](#2-kpi-measures)
3. [Workforce Measures](#3-workforce-measures)
4. [Year-on-Year Measures](#4-year-on-year-measures)
5. [RAG Status Measures](#5-rag-status-measures)
6. [Sector Benchmark Measures](#6-sector-benchmark-measures)
7. [Dynamic Titles and Labels](#7-dynamic-titles-and-labels)

---

## 1. Core I&E Measures

```dax
Total Income (£m) =
DIVIDE(
    SUMX( fact_ie_summary, fact_ie_summary[total_income_000s] ),
    1000,
    0
)

Patient Care Income (£m) =
DIVIDE(
    SUMX( fact_ie_summary, fact_ie_summary[patient_care_income_000s] ),
    1000,
    0
)

Other Income (£m) =
DIVIDE(
    SUMX( fact_ie_summary, fact_ie_summary[other_income_000s] ),
    1000,
    0
)

Total Expenditure (£m) =
DIVIDE(
    SUMX( fact_ie_summary, fact_ie_summary[total_expenditure_000s] ),
    1000,
    0
)

Operating Surplus (£m) =
DIVIDE(
    SUMX( fact_ie_summary, fact_ie_summary[operating_surplus_000s] ),
    1000,
    0
)

Net Surplus (£m) =
DIVIDE(
    SUMX( fact_ie_summary, fact_ie_summary[net_surplus_000s] ),
    1000,
    0
)

Total Pay (£m) =
DIVIDE(
    SUMX( fact_expenditure_breakdown, fact_expenditure_breakdown[pay_000s] ),
    1000,
    0
)

Total Non-Pay (£m) =
DIVIDE(
    SUMX( fact_expenditure_breakdown, fact_expenditure_breakdown[non_pay_000s] ),
    1000,
    0
)

Depreciation & Amortisation (£m) =
DIVIDE(
    SUMX( fact_expenditure_breakdown, fact_expenditure_breakdown[depreciation_amort_000s] ),
    1000,
    0
)

Drugs Cost (£m) =
DIVIDE(
    SUMX( fact_expenditure_breakdown, fact_expenditure_breakdown[drugs_cost_000s] ),
    1000,
    0
)
```

*No `Clinical Negligence £m` measure — `fact_expenditure_breakdown` (from `v_expenditure_breakdown`) has no
`clinical_negligence_000s` column. The SQL view was never extended to break that line out separately, so
clinical negligence stays folded into `non_pay_000s`.*

---

## 2. KPI Measures

```dax
-- ── EBITDA ────────────────────────────────────────────────────────────────

EBITDA (£m) =
DIVIDE(
    SUMX( fact_kpis, fact_kpis[ebitda_000s] ),
    1000,
    0
)

EBITDA Margin % =
-- Weighted sector EBITDA margin (not average of averages)
DIVIDE(
    SUMX( fact_kpis, fact_kpis[ebitda_000s] ),
    SUMX( fact_kpis, fact_kpis[total_income_000s] ),
    BLANK()
) * 100

-- ── Pay ───────────────────────────────────────────────────────────────────

Pay % of Income =
DIVIDE(
    SUMX( fact_kpis, fact_kpis[pay_000s] ),
    SUMX( fact_kpis, fact_kpis[total_income_000s] ),
    BLANK()
) * 100

-- ── Net Surplus ───────────────────────────────────────────────────────────

Net Surplus Margin % =
DIVIDE(
    SUMX( fact_ie_summary, fact_ie_summary[net_surplus_000s] ),
    SUMX( fact_ie_summary, fact_ie_summary[total_income_000s] ),
    BLANK()
) * 100

-- ── Deficit counts ────────────────────────────────────────────────────────

Deficit Trusts =
COUNTROWS(
    FILTER( fact_kpis, fact_kpis[operating_surplus_000s] < 0 )
)

Surplus Trusts =
COUNTROWS(
    FILTER( fact_kpis, fact_kpis[operating_surplus_000s] >= 0 )
)

Total Trusts =
DISTINCTCOUNT( fact_kpis[org_code] )

Deficit % =
DIVIDE( [Deficit Trusts], [Total Trusts], BLANK() ) * 100
```

---

## 3. Workforce Measures

```dax
Total WTE =
SUMX( fact_workforce, fact_workforce[total_wte] )

Total Staff Cost (£m) =
DIVIDE(
    SUMX( fact_workforce, fact_workforce[total_staff_cost_000s] ),
    1000,
    0
)

Avg Cost per WTE (£000s) =
DIVIDE(
    SUMX( fact_workforce, fact_workforce[total_staff_cost_000s] ),
    SUMX( fact_workforce, fact_workforce[total_wte] ),
    BLANK()
)

Medical WTE =
SUMX( fact_workforce, fact_workforce[medical_wte] )

Nursing WTE =
SUMX( fact_workforce, fact_workforce[nursing_wte] )

Admin & Estates WTE =
SUMX( fact_workforce, fact_workforce[admin_estates_wte] )

Scientific & Tech WTE =
SUMX( fact_workforce, fact_workforce[scientific_tech_wte] )

Medical % of WTE =
DIVIDE( [Medical WTE], [Total WTE], BLANK() ) * 100

Nursing % of WTE =
DIVIDE( [Nursing WTE], [Total WTE], BLANK() ) * 100
```

---

## 4. Year-on-Year Measures

```dax
-- Requires a slicer connected to dim_financial_year[financial_year]

Prior Year =
VAR _current = SELECTEDVALUE( dim_financial_year[financial_year] )
RETURN
    SWITCH(
        _current,
        "2023/24", "2022/23",
        "2022/23", "2021/22",
        "2021/22", "2020/21",
        BLANK()
    )

Prior Year Income (£m) =
VAR _py = [Prior Year]
RETURN
    IF(
        NOT ISBLANK( _py ),
        CALCULATE(
            [Total Income (£m)],
            dim_financial_year[financial_year] = _py
        ),
        BLANK()
    )

Income YoY Growth % =
VAR _cy = [Total Income (£m)]
VAR _py = [Prior Year Income (£m)]
RETURN IF( NOT ISBLANK( _py ), DIVIDE( _cy - _py, _py, BLANK() ) * 100, BLANK() )

Prior Year EBITDA Margin % =
VAR _py = [Prior Year]
RETURN
    IF(
        NOT ISBLANK( _py ),
        CALCULATE(
            [EBITDA Margin %],
            dim_financial_year[financial_year] = _py
        ),
        BLANK()
    )

EBITDA Margin YoY pp =
-- Percentage point change in EBITDA margin vs prior year
[EBITDA Margin %] - [Prior Year EBITDA Margin %]

Prior Year Pay % =
VAR _py = [Prior Year]
RETURN
    IF(
        NOT ISBLANK( _py ),
        CALCULATE(
            [Pay % of Income],
            dim_financial_year[financial_year] = _py
        ),
        BLANK()
    )

Pay % YoY pp =
[Pay % of Income] - [Prior Year Pay %]

Prior Year Deficit Trusts =
VAR _py = [Prior Year]
RETURN
    IF(
        NOT ISBLANK( _py ),
        CALCULATE(
            [Deficit Trusts],
            dim_financial_year[financial_year] = _py
        ),
        BLANK()
    )

Deficit Trusts YoY Change =
[Deficit Trusts] - [Prior Year Deficit Trusts]
```

---

## 5. RAG Status Measures

```dax
-- Returns a colour string for use in conditional formatting or field value visuals

EBITDA RAG =
VAR _margin = [EBITDA Margin %]
RETURN
    SWITCH(
        TRUE(),
        ISBLANK( _margin ),    "Grey",
        _margin >= 5,           "Green",
        _margin >= 2,           "Amber",
        "Red"
    )

Surplus RAG =
VAR _margin = [Net Surplus Margin %]
RETURN
    SWITCH(
        TRUE(),
        ISBLANK( _margin ),    "Grey",
        _margin >= 0,           "Green",
        _margin >= -2,          "Amber",
        "Red"
    )

Pay RAG =
-- RAG based on acute sector benchmark (65% amber threshold)
-- Adjust threshold via What-If parameter or sector slicer context for multi-sector use
VAR _pay_pct = [Pay % of Income]
RETURN
    SWITCH(
        TRUE(),
        ISBLANK( _pay_pct ),   "Grey",
        _pay_pct < 65,          "Green",
        _pay_pct < 70,          "Amber",
        "Red"
    )

-- ── RAG hex colours for conditional formatting ────────────────────────────

EBITDA RAG Colour =
SWITCH(
    [EBITDA RAG],
    "Green", "#009639",
    "Amber", "#FFB81C",
    "Red",   "#DA291C",
    "#E8EDEE"
)

Surplus RAG Colour =
SWITCH(
    [Surplus RAG],
    "Green", "#009639",
    "Amber", "#FFB81C",
    "Red",   "#DA291C",
    "#E8EDEE"
)

Pay RAG Colour =
SWITCH(
    [Pay RAG],
    "Green", "#009639",
    "Amber", "#FFB81C",
    "Red",   "#DA291C",
    "#E8EDEE"
)
```

---

## 6. Sector Benchmark Measures

```dax
-- Sector average EBITDA margin — for use in scatter plot reference line or tooltip
-- Requires fact_sector_benchmarks table in the model
-- Uses the pre-aggregated avg_ebitda_margin_pct column already computed in v_kpis / sector_benchmarks.csv,
-- rather than re-deriving it from raw totals

Sector Benchmark EBITDA % =
AVERAGEX(
    VALUES( fact_sector_benchmarks[sector] ),
    CALCULATE( AVERAGE( fact_sector_benchmarks[avg_ebitda_margin_pct] ) )
)

-- EBITDA vs sector benchmark (for KPI variance visual)
EBITDA vs Sector Benchmark pp =
[EBITDA Margin %] - [Sector Benchmark EBITDA %]
```

---

## 7. Dynamic Titles and Labels

```dax
-- Use these in the Title field of visuals so they respond to slicer selections

Selected Year =
SELECTEDVALUE( dim_financial_year[financial_year], "All Years" )

Selected Sector =
SELECTEDVALUE( dim_trust[sector], "All Sectors" )

Selected Region =
SELECTEDVALUE( dim_trust[region], "All Regions" )

Page Title - I&E =
"Income & Expenditure - " & [Selected Year] & " | " & [Selected Sector]

Surplus Label =
VAR _val = [Operating Surplus (£m)]
RETURN
    IF(
        _val >= 0,
        "£" & FORMAT( _val, "0.0" ) & "m surplus",
        "£" & FORMAT( ABS( _val ), "0.0" ) & "m deficit"
    )

EBITDA Label =
FORMAT( [EBITDA Margin %], "0.0" ) & "% EBITDA margin"

Deficit Count Label =
FORMAT( [Deficit Trusts], "0" ) & " of " & FORMAT( [Total Trusts], "0" ) & " trusts in deficit"
```

---

## Usage Notes

- **Never** create measures inside a report visual — all measures live in the Measures table
- **Never** use implicit measures (dragging a column onto a visual without an explicit measure)
- Use `DIVIDE()` instead of `/` to handle divide-by-zero gracefully
- Filter `dim_financial_year` via a slicer on every page — do not hardcode year values in measures
- Use `SELECTEDVALUE()` with a default for measures that need to be robust to no-selection state
- All `£m` measures divide `_000s` columns by 1,000 — verify units when building new measures
