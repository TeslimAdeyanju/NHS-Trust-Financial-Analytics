# Reports Layer — Narrative Standards

This describes the one report type that actually exists in `reports/`:
[`nhs_sector_financial_review_2324.md`](nhs_sector_financial_review_2324.md), an annual sector-level
outturn analysis built on the `nhs_finance` data. There is no monthly or quarterly board-report pipeline,
and no budget/variance data source to report against — see the top-level `CLAUDE.md` for why.

## What this report is

An **annual, sector-wide outturn narrative** — not a single-Trust board report. It reads like something a
national or regional finance analytics function would produce from the consolidated TAC data: three-year
trend, income/expenditure composition, sector-by-sector comparison, and a set of data-backed findings. It
is actuals-only, in line with the rest of this project — there is no `[FORECAST]` or `[PLAN]` figure
anywhere in it, and none should be added.

## Structure (as actually used)

```text
1. Executive Summary          (headline deficit/surplus swing, 2-3 driving factors)
2. Income & Expenditure — Sector Outturn
   2.1 Three-Year Trend        (income, expenditure, surplus/deficit, deficit-trust count)
   2.2 Income Composition      (patient care vs other income, API contract mechanism)
   2.3 Expenditure Composition (pay / non-pay / depreciation split)
3. Sector-by-sector comparison (Acute / Mental Health / Specialist / Community / Ambulance)
4. Findings and conclusion
```

## Reporting Convention

- NHS Financial Reporting Manual (FReM) / IFRS as adopted for the public sector — cited in the report
  header, not enforced by any code in this project
- Currency: **£m** in narrative text (not `_000s`), consistent with `CLAUDE.md`'s rule that report output
  spells out thousands/millions rather than using the `_000s` suffix convention used in code and CSVs
- Percentages: 1 decimal place — `4.3%`, not `4%` or `4.32%`

## Tone and Language

- Plain English suitable for a non-finance board member or a general reader
- Lead every section with the bottom line, then explain it — state the position before the cause
- Active voice: "the sector recorded a deficit" not "a deficit was recorded"
- Every figure should be traceable back to a `v_kpis` / `v_income_expenditure` / `v_trust_annual_scorecard`
  query — this report doesn't introduce numbers that aren't in the warehouse

## Do Not

- Do not present a forecast, budget, or plan figure as an actual — this dataset has no such source, so
  anything of that kind would necessarily come from outside this pipeline and must be labelled as such if
  it's ever added
- Do not include Trust- or patient-identifiable narrative beyond what NHS England already publishes at
  Trust level in TAC (org name, ODS code, sector, region)
- Do not invent a monthly/quarterly report cadence, `[FORECAST]`/`[ACTUAL]` tagging convention, or
  variance-commentary template — none of that applies to an annual, actuals-only dataset
