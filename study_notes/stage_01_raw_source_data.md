# Stage 1 — Raw Source Data

> This stage is about understanding the exact shape of the data before any code runs.
> The Python pipeline receives these files and has to deal with exactly what NHS England
> published — no cleaning, no reformatting.

---

## The 6 Files

```
data/raw/
  TAC_NHS_trusts_2021-22.xlsx             16MB  —  66 NHS Trusts
  TAC_NHS_foundation_trusts_2021-22.xlsx  33MB  — 140 Foundation Trusts
  TAC_NHS_trusts_2022-23.xlsx             20MB  —  66 NHS Trusts
  TAC_NHS_foundation_trusts_2022-23.xlsx  36MB  — 140 Foundation Trusts
  TAC_NHS_trusts_2023-24.xlsx             18MB  —  66 NHS Trusts
  TAC_NHS_foundation_trusts_2023-24.xlsx  38MB  — 140 Foundation Trusts
```

**Why 2 files per year?** NHS Trusts and Foundation Trusts are published separately.
Same column structure, different populations. The pipeline treats them identically —
the filename tells the code which type it is.

**Why are they large?** Long/narrow format — 10,000+ rows per Trust.
66 Trusts × ~7,000 rows ≈ 481,000 rows per NHS Trusts file.

**The illustrative file** (`TAC_illustrative_2023-24.xlsx`) is a reference schema file
showing all SubCodes and descriptions. The pipeline explicitly skips it:
```python
# load_tac_data.py:365
if "illustrative" not in p.name.lower()
```

---

## Inside Each File: Two Sheets That Matter

### Sheet 1: "List of Providers"

Small lookup table — one row per Trust (66 or 140 rows).

| Column                  | Example                           |
|-------------------------|-----------------------------------|
| Full name of Provider   | `Barnsley Hospital NHS Foundation Trust` |
| NHS code                | `RFF`                             |
| Region                  | `Yorkshire and Humber`            |
| Sector                  | `Acute`                           |
| Comments                | blank, or exclusion reason        |

**Purpose:** Provides the ODS code for each Trust by name.
The "All data" sheet has names but not codes — this sheet resolves the gap.

The pipeline keeps only rows where `org_code` is exactly 3 characters:
```python
df = df[df["org_code"].str.len() == 3]   # drops blank rows, header artefacts
```

---

### Sheet 2: "All data"

The main data sheet. ~481,000 rows (NHS Trusts) or ~1.1M rows (Foundation Trusts).

**7 columns exactly:**

| Column           | Type    | Description                                    | Example        |
|------------------|---------|------------------------------------------------|----------------|
| OrganisationName | string  | Full legal name of the Trust                   | `Barts Health NHS Trust` |
| WorkSheetName    | string  | TAC schedule name                              | `TAC02 SoCI`   |
| TableID          | integer | Table number within the sheet                  | `1`            |
| MainCode         | string  | Sheet + CY/PY + table identifier               | `A02CY01`      |
| RowNumber        | integer | Row position in original form                  | `12`           |
| SubCode          | string  | Unique line item identifier                    | `SCI0100A`     |
| Total            | integer | Value in £000s                                 | `2047312`      |

**Sample rows (illustrative):**

```
OrganisationName          WorkSheetName   MainCode   SubCode    Total
────────────────────────  ──────────────  ─────────  ─────────  ──────────
Barts Health NHS Trust    TAC02 SoCI      A02CY01    SCI0100A   2047312   ← patient care income CY
Barts Health NHS Trust    TAC02 SoCI      A02CY01    SCI0110A    124508   ← other income CY
Barts Health NHS Trust    TAC02 SoCI      A02CY01    SCI0125A  -2089441   ← total expenditure CY (negative)
Barts Health NHS Trust    TAC02 SoCI      A02CY01    SCI0140A     82379   ← operating surplus CY
Barts Health NHS Trust    TAC08 Op Exp    A08CY01    EXP0130    1187432   ← staff costs CY
Barts Health NHS Trust    TAC02 SoCI      A02PY01    SCI0100A   1901877   ← patient care income PY ← DROP
```

The PY row (last line) is 2022/23 data embedded inside the 2023/24 file.
It must be dropped to avoid double-counting when all 6 files are combined.

---

## A Key Inconsistency Across File Versions

NHS England changed column names between 2021/22 and later files:

| 2021/22 column name   | 2022/23+ column name | What it is        |
|-----------------------|----------------------|-------------------|
| `Organisation Name`   | `OrganisationName`   | Trust name        |
| `Value number`        | `Total`              | The £000s value   |

The pipeline handles this silently:
```python
# load_tac_data.py:132-137
col_map = {
    "Organisation Name": "OrganisationName",
    "Value number":      "Total",
    "Value Number":      "Total",
}
df = df.rename(columns=col_map)
```

Without this, pandas would create a DataFrame with an unexpected column name and the
pipeline would crash with a "missing column" error.

**This is a real-world data engineering problem:** external source files change format
over time and the pipeline must absorb those changes transparently.

---

## What the Pipeline Reads from the Filename (Before Opening the File)

The pipeline extracts two critical facts from the filename itself:

**1. Financial year:**
```python
# filename: TAC_NHS_trusts_2023-24.xlsx
YEAR_RE = re.compile(r"(\d{4})-(\d{2})")
# matches "2023" and "24" → returns "2023/24"
```

**2. Trust type:**
```python
"FOUNDATION_TRUST" if "foundation" in filename.lower() else "NHS_TRUST"
```

No trust type column exists inside the file. It is inferred purely from the filename.
`trust_type` becomes a column on every staging and fact table row.

---

## Before/After Row Counts

```
NHS Trusts 2023-24 file:
  Raw (CY + PY combined):   ~481,000 rows
  After CY filter:          ~241,000 rows

Foundation Trusts 2023-24 file:
  Raw (CY + PY combined):  ~1,100,000 rows
  After CY filter:           ~550,000 rows

All 6 files combined (CY only):
  Total fact rows:         ~2,180,000 rows  → fct_tac
```

---

## Raw Data Quality Issues and How They Are Handled

| Issue | How handled |
|-------|-------------|
| `Total` column arrives as float | `pd.to_numeric().fillna(0).astype("int64")` |
| Organisation names have trailing spaces | `.str.strip()` on every string column |
| `Comments ` column has trailing space in header | Rename both `"Comments "` and `"Comments"` variants |
| Negative values in expenditure | Valid — stored as-is; sign convention follows TAC |
| Zero values | Valid — do not treat as null |
| PY rows mixed with CY rows | Filter: `df[df["year_type"] == "CY"]` |

---

## Tracing One Row End-to-End (Preview of Stage 2)

```
Raw Excel row:
  OrganisationName = "Barts Health NHS Trust"
  WorkSheetName    = "TAC02 SoCI"
  MainCode         = "A02CY01"
  SubCode          = "SCI0100A"
  Total            = 2047312

After ingestion pipeline (Stage 2):
  org_code         = "R1H"              ← resolved via join to provider list
  financial_year   = "2023/24"          ← from filename
  worksheet_name   = "TAC02 SoCI"       ← same
  main_code        = "A02CY01"          ← same
  sub_code         = "SCI0100A"         ← same
  total_000s       = 2047312            ← same value, renamed with _000s suffix
  trust_type       = "FOUNDATION_TRUST" ← from filename
```

The only transformation at this stage is: **name → ODS code** (via join).
The value itself is never changed.

---

## Stage 1 Summary

| What you see in the raw file           | What it means                              |
|----------------------------------------|--------------------------------------------|
| 2 sheets per file                      | "List of Providers" = lookup; "All data" = facts |
| 7 columns in "All data"                | Minimal structure to identify any line for any Trust |
| CY and PY rows mixed                   | Must filter to CY only across all 6 files |
| Name in "All data", code in provider list | A join is required to resolve ODS codes |
| Column names differ in 2021/22         | Pipeline handles format changes silently   |
| Total in £000s                         | Never divide or multiply — store as-is with `_000s` suffix |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [data/raw/](../data/raw/) | Open any TAC xlsx in Excel — examine both sheets |
| [agent_docs/data_dictionary.md](../agent_docs/data_dictionary.md) | Full SubCode reference, MainCode format, data quality notes |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md) §4 | TAC publication explanation, file contents walkthrough |
| [python/ingestion/load_tac_data.py](../python/ingestion/load_tac_data.py) | `read_provider_list()` and `read_all_data()` functions |

---

*Previous: [Stage 0 — Domain Context](stage_00_domain_context.md)*
*Next: [Stage 2 — Python Ingestion Pipeline](stage_02_python_ingestion.md)*
