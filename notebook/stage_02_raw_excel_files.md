# Stage ② — Raw Excel Files

> This stage is about understanding the exact shape of the data before any code runs. The Python
> pipeline receives these files and has to deal with exactly what NHS England published — no cleaning,
> no reformatting, nothing assumed.

---

## The 6 Files

```text
data/raw/
  TAC_NHS_trusts_2021-22.xlsx             16MB  —  66 NHS Trusts
  TAC_NHS_foundation_trusts_2021-22.xlsx  33MB  — 140 Foundation Trusts
  TAC_NHS_trusts_2022-23.xlsx             20MB  —  66 NHS Trusts
  TAC_NHS_foundation_trusts_2022-23.xlsx  36MB  — 140 Foundation Trusts
  TAC_NHS_trusts_2023-24.xlsx             18MB  —  66 NHS Trusts
  TAC_NHS_foundation_trusts_2023-24.xlsx  38MB  — 140 Foundation Trusts
```

**Why 2 files per year?** NHS Trusts and Foundation Trusts are published separately. Same column
structure, different populations. The pipeline treats them identically — the filename tells the code
which type it is.

**Why are they large?** Long/narrow format — 10,000+ rows per trust. 66 trusts × ~7,000 rows ≈ 481,000
rows in an NHS Trusts file alone.

**The illustrative file** (`TAC_illustrative_2023-24.xlsx`) is a reference schema file showing every
SubCode and its description, not real trust data. The pipeline explicitly skips it:

```python
# python/ingestion/load_tac_data.py
files = sorted(
    p for p in RAW_DIR.glob("TAC_NHS_*.xlsx")
    if "illustrative" not in p.name.lower()
)
```

---

## Inside Each File: Two Sheets That Matter

### Sheet 1 — "List of Providers"

Small lookup table, one row per trust (66 or 140 rows).

| Column                | Example                                  |
|------------------------|-------------------------------------------|
| Full name of Provider  | `Barnsley Hospital NHS Foundation Trust`  |
| NHS code               | `RFF`                                     |
| Region                 | `Yorkshire and Humber`                    |
| Sector                 | `Acute`                                   |

**Purpose:** provides the ODS code for each trust by name. The "All data" sheet has names, not codes —
this sheet resolves that gap.

The pipeline keeps only rows where `org_code` is exactly 3 characters:

```python
df = df[df["org_code"].str.len() == 3]   # drops blank rows, header artefacts
```

### Sheet 2 — "All data"

The main data sheet: ~481,000 rows (NHS Trusts file) or ~1.1M rows (Foundation Trusts file), long/narrow,
exactly 7 columns.

| Column           | Type    | Description                          | Example                  |
|-------------------|---------|----------------------------------------|----------------------------|
| OrganisationName  | string  | Full legal name of the trust           | `Barts Health NHS Trust`  |
| WorkSheetName     | string  | TAC schedule name                      | `TAC02 SoCI`               |
| TableID           | integer | Table number within the sheet          | `1`                         |
| MainCode          | string  | Sheet + CY/PY + table identifier       | `A02CY01`                   |
| RowNumber         | integer | Row position in original form          | `12`                         |
| SubCode           | string  | Unique line item identifier            | `SCI0100A`                   |
| Total             | integer | Value in £000s                         | `2047312`                     |

```text
OrganisationName          WorkSheetName   MainCode   SubCode    Total
────────────────────────  ──────────────  ─────────  ─────────  ──────────
Barts Health NHS Trust    TAC02 SoCI      A02CY01    SCI0100A   2047312   ← patient care income CY
Barts Health NHS Trust    TAC02 SoCI      A02CY01    SCI0140A     82379   ← operating surplus CY
Barts Health NHS Trust    TAC08 Op Exp    A08CY01    EXP0130    1187432   ← staff costs CY
Barts Health NHS Trust    TAC02 SoCI      A02PY01    SCI0100A   1901877   ← patient care income PY ← DROP
```

The last row is 2022/23 data embedded inside the 2023/24 file — every annual file carries both years side
by side for comparison, and the PY row must be dropped to avoid double-counting once all six files are
combined (see [stage ③](stage_03_mysql_staging.md) for where that filter actually runs).

---

## A Key Inconsistency Across File Versions

NHS England changed column names between 2021/22 and later files:

| 2021/22 column name | 2022/23+ column name | What it is      |
|-----------------------|-----------------------|-------------------|
| `Organisation Name`   | `OrganisationName`   | Trust name        |
| `Value number`        | `Total`               | The £000s value   |

The pipeline handles this silently:

```python
col_map = {
    "Organisation Name": "OrganisationName",
    "Value number":      "Total",
    "Value Number":      "Total",
}
df = df.rename(columns=col_map)
```

Without this, pandas would produce a DataFrame with an unexpected column name and the pipeline would fail
with a missing-column error on the 2021/22 files specifically. This is a real-world data-engineering
problem: an external source changed format mid-series, and the pipeline has to absorb that transparently
rather than special-casing "the old files" by hand.

---

## What the Pipeline Reads from the Filename — Before Opening the File

Two critical facts live only in the filename, not inside the workbook:

```python
YEAR_RE = re.compile(r"(\d{4})-(\d{2})")

def filename_to_financial_year(filename: str) -> str:
    match = YEAR_RE.search(filename)
    return f"{match.group(1)}/{match.group(2)}"   # "2023-24" → "2023/24"

def filename_to_trust_type(filename: str) -> str:
    return "FOUNDATION_TRUST" if "foundation" in filename.lower() else "NHS_TRUST"
```

Both `financial_year` and `trust_type` are attached to every row of data as extra columns before anything
else happens. Rename a file and the pipeline mis-tags every row inside it — the exact filenames matter.

---

## Raw Data Quality Issues and How They're Handled

| Issue | How handled |
|-------|-------------|
| `Total` column arrives as float (Excel `NaN` for blanks) | Read as `float`, `fillna(0)`, cast to `int64` only after CY/PY filtering |
| Organisation names have trailing spaces | `.str.strip()` on every string column |
| Negative values in expenditure | Valid — stored as-is; sign convention follows TAC, not remapped |
| PY rows mixed with CY rows | Filtered on `main_code` containing `"PY"` before any row is written |

---

## Stage ② Summary

| What you see in the raw file              | What it means                                         |
|---------------------------------------------|----------------------------------------------------------|
| 2 sheets per file                           | "List of Providers" = lookup; "All data" = facts        |
| 7 columns in "All data"                     | Minimal structure to identify any line for any trust     |
| CY and PY rows mixed                        | Must filter to CY only across all six files              |
| Name in "All data", code in provider list   | A join is required to resolve ODS codes — see stage ③   |
| Column names differ in 2021/22              | Pipeline handles format changes silently                 |
| Total in £000s                              | Never divide or multiply here — store as-is              |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [data/raw/](../data/raw/) | Open any TAC `.xlsx` in Excel — examine both sheets directly |
| [agent_docs/data_dictionary.md](../agent_docs/data_dictionary.md) | Full SubCode reference, MainCode format, data-quality notes |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md), stage ② | The narrative version, plus the "how I sourced the data" story |
| [python/ingestion/load_tac_data.py](../python/ingestion/load_tac_data.py) | `filename_to_financial_year()`, `filename_to_trust_type()`, `read_provider_list()`, `read_all_data()` |

---

*Previous: [Stage ① — NHS England (Source)](stage_01_nhs_england_source.md)*
*Next: [Stage ③ — MySQL Staging](stage_03_mysql_staging.md)*
