# Stage 0 — NHS Domain Context

> Before touching a single line of code, you need to understand the world the project is
> modelling. Every design decision in the Python, SQL, and Power BI layers traces back to
> NHS financial reporting rules.

---

## 1. The Financial Year Convention

The NHS financial year runs **1 April → 31 March**. This is a government accounting convention —
most UK public bodies use it.

| Label | Month     | Quarter |
|-------|-----------|---------|
| M01   | April     | Q1      |
| M02   | May       | Q1      |
| M03   | June      | Q1      |
| M04   | July      | Q2      |
| M05   | August    | Q2      |
| M06   | September | Q2      |
| M07   | October   | Q3      |
| M08   | November  | Q3      |
| M09   | December  | Q3      |
| M10   | January   | Q4      |
| M11   | February  | Q4      |
| M12   | March     | Q4      |

**Rule for the code:** Every date filter uses `financial_year` (e.g. `2023/24`) and
`period_label` (e.g. `M06`) — never a calendar year, never a calendar month name.
You will never see `WHERE MONTH(date) = 9`. You will always see `WHERE period_label = 'M06'`.

The format `2023/24` encodes that the year straddles two calendar years. `24` = two-digit
shorthand for the March end. This is the mandatory NHS format.

---

## 2. The Money Convention: £000s

All monetary values in every table, view, CSV, and report are stored in **GBP thousands (£000s)**.

So: `total_income_000s = 2047000` means **£2.047 billion**.

**Why £000s?**
- Storing in full pounds = 9-digit integers everywhere, hard to read
- Storing in £millions = rounding noise on small line items (a £342,000 drug rebate becomes £0.3m)
- £000s = whole numbers, no rounding noise, fits neatly into integer columns

**The `_000s` suffix convention:** Every monetary column is named with `_000s` —
`total_income_000s`, `pay_000s`, `drugs_cost_000s`. This prevents accidentally mixing
£000s and £m columns in the same calculation.

**In Power BI**, DAX converts to £m for display:
```dax
Total Income (£m) = DIVIDE(SUM(kpis[total_income_000s]), 1000, 0)
```

---

## 3. The ODS Code — Why Organisation Names Are Not Enough

Every NHS organisation has a permanent 3-character **ODS code** (Organisation Data Service code):
- Barts Health NHS Trust = `R1H`
- Guy's and St Thomas' = `RJ1`

ODS codes are stable identifiers — they survive mergers, renames, and status changes.

**The problem:** The raw TAC Excel files only contain the full legal name in the "All data" sheet —
not the ODS code. Full names are fragile: they change, have trailing spaces, encoding differences,
and capitalisation variations across file versions.

**The solution:** The ingestion pipeline joins "All data" (names only) with the "List of Providers"
sheet (names + codes) to resolve every row to its ODS code. That 3-character code then becomes
the primary key throughout the entire warehouse.

---

## 4. The TAC Structure — Long/Narrow Format

TAC = **Trust Accounts Consolidation** — NHS England's annual collection of audited accounts
from all 206 Trusts, published in a standardised Excel format.

**Critical insight:** The data is in **long/narrow format**. Instead of one column per financial
line item per Trust, there is **one row per line item per Trust**. For one Trust in one year,
there are ~10,000+ rows — one for each SubCode across all 19 TAC schedules.

**The 7 columns:**

| Column          | Type    | Description                                        | Example        |
|-----------------|---------|----------------------------------------------------|----------------|
| OrganisationName | string | Full legal name of the Trust                       | `Barts Health NHS Trust` |
| WorkSheetName   | string  | TAC schedule name                                  | `TAC02 SoCI`   |
| TableID         | integer | Table number within the sheet                      | `1`            |
| MainCode        | string  | Column identifier (sheet + CY/PY + table)          | `A02CY01`      |
| RowNumber       | integer | Row position in original form                      | `12`           |
| SubCode         | string  | Unique line item identifier                        | `SCI0100A`     |
| Total           | integer | Value in £000s                                     | `350689`       |

**MainCode format:** `A{sheet_number}{CY|PY}{table_number}`
- `A02CY01` → Sheet TAC02 (SoCI), Current Year, Table 1
- `A08PY01` → Sheet TAC08 (Op Exp), Prior Year, Table 1

---

## 5. The SubCode — The Most Important Concept

A SubCode uniquely identifies a single financial line item within a single TAC schedule.
It is consistent across all 206 Trusts, all 3 years, all 6 files.

The analytics layer works entirely by filtering on SubCodes. There is no column called
`patient_care_income` in the fact table; instead, every view writes `WHERE sub_code = 'SCI0100A'`.

**Key SubCodes to memorise:**

| SubCode    | What it is                              | Schedule |
|------------|-----------------------------------------|----------|
| `SCI0100A` | Patient care income (main revenue line) | TAC02    |
| `SCI0110A` | Other operating income                  | TAC02    |
| `SCI0125A` | Total operating expenses                | TAC02    |
| `SCI0140A` | Operating surplus / (deficit)           | TAC02    |
| `SCI0240`  | Net surplus / (deficit) for the year    | TAC02    |
| `EXP0130`  | Staff and executive directors costs     | TAC08    |
| `EXP0240`  | Depreciation                            | TAC08    |
| `EXP0250`  | Amortisation                            | TAC08    |
| `EXP0290A` | Clinical negligence premium             | TAC08    |
| `EXP0390`  | Total operating expenditure             | TAC08    |
| `STA0250`  | Total staff costs                       | TAC09    |
| `STA0410`  | Total average WTE (headcount)           | TAC09    |

**The 19 TAC Schedules:**

| Schedule              | Content                             |
|-----------------------|-------------------------------------|
| TAC02 SoCI            | Summary P&L (income, expenditure, surplus) |
| TAC03 SoFP            | Balance sheet                       |
| TAC05 SoCF            | Cash flow statement                 |
| TAC06 Op Inc 1        | Patient care income (by nature + source) |
| TAC07 Op Inc 2        | Other operating income              |
| TAC08 Op Exp          | Operating expenditure (detailed)    |
| TAC09 Staff           | Staff costs and WTE numbers         |
| TAC11 Finance & other | Finance income, finance expense, PDC dividend |
| TAC14 PPE             | Property, plant and equipment       |
| TAC14A RoU Assets     | Right-of-use assets (IFRS 16 leases) |
| TAC18 Receivables     | Debtors                             |
| TAC19 CCE             | Cash and cash equivalents           |
| TAC20 Payables        | Creditors                           |

---

## 6. CY vs PY — The Double-Counting Trap

Each annual Excel file contains **both** current year (CY) and prior year (PY) data —
NHS accounts always show two years side by side for comparison.

```
TAC_NHS_trusts_2023-24.xlsx contains:
  - 2023/24 data  (MainCode contains "CY")  ← keep this
  - 2022/23 data  (MainCode contains "PY")  ← skip this

TAC_NHS_trusts_2022-23.xlsx contains:
  - 2022/23 data  (MainCode contains "CY")  ← keep this
  - 2021/22 data  (MainCode contains "PY")  ← skip this
```

If all 6 files were loaded without filtering, 2022/23 data would be loaded **twice**.
The ingestion pipeline prevents this: `WHERE main_code NOT LIKE '%PY%'`.

---

## 7. EBITDA — Why Not Just Use Net Surplus?

```
Net surplus = income − ALL costs  (including depreciation, interest, PDC dividend)
EBITDA      = income − pay − non-pay running costs  (BEFORE depreciation and finance charges)

EBITDA = Operating Surplus + Depreciation + Amortisation
```

**Depreciation** is a non-cash accounting charge — it reflects ageing of buildings/equipment,
but no money actually leaves the organisation that year. Stripping it out gives a cleaner
picture of cash generation from operations.

**PDC dividend** is a mandatory government charge on publicly funded assets — outside the
Trust's control entirely.

EBITDA answers: *"How well is this Trust running its day-to-day operations?"* — without
penalising it for capital-heavy estate or government finance structures it cannot change.

**RAG thresholds:**

| Status | EBITDA Margin % | Meaning                           |
|--------|----------------|-----------------------------------|
| Green  | ≥ 2%           | Financially sustainable           |
| Amber  | 0–2%           | Fragile, under watch              |
| Red    | < 0%           | In deficit, regulatory risk       |

In 2023/24, **60% of NHS Trusts** were at Amber or Red — the sector was in widespread distress.

---

## 8. The NHS Financial Crisis: The Numbers

| Year    | Sector balance     | Trusts in deficit   |
|---------|--------------------|---------------------|
| 2021/22 | +£1.6bn surplus    | 37 of 211 (18%)     |
| 2022/23 | +£148m surplus     | 85 of 207 (41%)     |
| 2023/24 | −£1.6bn deficit    | 124 of 206 (60%)    |

A **£3.2bn swing in two years.** Driven by:
1. Post-COVID cost base that didn't unwind
2. Inflation surge in energy, supplies, drugs
3. Above-inflation pay awards (5–6%), only 60–70% centrally funded
4. Agency staffing premium (30–50% above substantive rates)
5. Clinical negligence premiums growing year-on-year

---

## Stage 0 Summary

| Concept        | The Rule                                                      |
|----------------|---------------------------------------------------------------|
| Financial year | April–March, labelled `2023/24`, periods `M01`–`M12`         |
| Money units    | Always £000s, column suffix `_000s`, convert to £m for display only |
| Trust identity | ODS code (3 chars) is the permanent key, not the name        |
| Data format    | Long/narrow — one row per SubCode per Trust per year         |
| SubCode        | Unique identifier for each financial line item               |
| CY vs PY       | Load CY rows only — every file contains both years           |
| EBITDA         | Operating surplus + depreciation; strips out non-cash charges |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [CLAUDE.md](../CLAUDE.md) | NHS FReM rules, naming conventions, KPI list |
| [agent_docs/kpi_definitions.md](../agent_docs/kpi_definitions.md) | KPI formulas + RAG thresholds |
| [agent_docs/data_dictionary.md](../agent_docs/data_dictionary.md) | TAC columns, SubCode reference, data quality notes |
| [agent_docs/report_calendar.md](../agent_docs/report_calendar.md) | M01–M12 period table, monthly close cycle |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md) §1–3 | NHS background, financial crisis, project scope |

---

*Next: [Stage 1 — Raw Source Data](stage_01_raw_source_data.md)*
