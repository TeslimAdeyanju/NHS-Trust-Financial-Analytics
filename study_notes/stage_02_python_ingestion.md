# Stage 2 — Python Ingestion Pipeline

> This is the engine of the project. It reads all 6 Excel files and loads them into MySQL.
> The entire script is one file: `python/ingestion/load_tac_data.py` (395 lines).

---

## The Call Chain

```
main()
  └── process_file(path)          ← called once per Excel file (6 times)
        ├── read_provider_list()  ← Sheet 1: name → ODS code lookup
        ├── read_all_data()       ← Sheet 2: 481K–1.1M rows, CY only
        ├── validate()            ← quality checks before writing anything
        ├── load_staging()        ← writes to nhs_stg (MySQL)
        ├── populate_dim_trust()  ← upserts 206 trusts into dim_trust
        └── promote_to_fact()     ← joins staging → upserts into fct_tac
```

Each function has exactly one responsibility.

---

## 1. `main()` — Entry Point

```python
files = sorted(
    p for p in RAW_DIR.glob("TAC_NHS_*.xlsx")
    if "illustrative" not in p.name.lower()
)
```

- `Path.glob()` auto-discovers files — no hardcoded filenames
- `"illustrative"` exclusion skips the NHS reference schema file
- `sorted()` ensures alphabetical order → 2021-22 loads before 2023-24
  (important: `first_year_seen` on `dim_trust` is set correctly only if files are processed oldest-first)

Final output after all 6 files:
```
COMPLETE
  dim_trust rows : 206
  fct_tac rows   : 2,179,740
```

---

## 2. `process_file()` — One File's Full Journey

Two helpers extract metadata from the filename before opening the file:

```python
# "TAC_NHS_trusts_2023-24.xlsx" → "2023/24"
YEAR_RE = re.compile(r"(\d{4})-(\d{2})")
def filename_to_financial_year(filename):
    match = YEAR_RE.search(filename)
    return f"{match.group(1)}/{match.group(2)}"

# "foundation" in filename → "FOUNDATION_TRUST", else "NHS_TRUST"
def filename_to_trust_type(filename):
    return "FOUNDATION_TRUST" if "foundation" in filename.lower() else "NHS_TRUST"
```

Both `financial_year` and `trust_type` are then attached to every row of data as extra columns.
They come from the **filename**, not the file contents.

---

## 3. `read_provider_list()` — The Lookup Table

```python
df = pd.read_excel(path, sheet_name="List of Providers", header=0)
df = df.rename(columns={
    "Full name of Provider": "organisation_name",
    "NHS code":              "org_code",
    "Region":                "region",
    "Sector":                "sector",
})
df["org_code"] = df["org_code"].astype(str).str.strip()
df = df[df["org_code"].str.len() == 3]   # keep only valid ODS codes
```

Produces a small DataFrame (66 or 140 rows): `organisation_name → org_code`.

**Used for:**
1. Validation — check all names in "All data" appear here
2. Join in `promote_to_fact()` — to resolve names → ODS codes

The `str.len() == 3` filter drops extra header/footer rows that don't represent real Trusts.

---

## 4. `read_all_data()` — The Heavy Lifter

5 steps in sequence:

### Step A — Read the sheet (case-insensitive name lookup)
```python
sheet_name = find_sheet_name(path, "All data")  # handles "All data" vs "All Data"
df = pd.read_excel(path, sheet_name=sheet_name, header=0, dtype={
    "OrganisationName": str,
    "WorkSheetName":    str,
    "TableID":          "Int64",   # nullable integer
    "MainCode":         str,
    "RowNumber":        "Int64",
    "SubCode":          str,
    "Total":            float,     # float first → NaN-safe, cast to int later
})
```

`Total` is read as `float` because Excel cells with missing values become `NaN`,
and `NaN` can only exist in a float column. Cast to `int64` happens in Step E.

### Step B — Normalise column names (2021/22 vs later)
```python
col_map = {
    "Organisation Name": "OrganisationName",  # 2021/22 had a space
    "Value number":      "Total",             # 2021/22 called it "Value number"
    "Value Number":      "Total",
}
df = df.rename(columns=col_map)
```

### Step C — Drop null rows, strip strings
```python
df = df.dropna(subset=["organisation_name", "sub_code", "total"])
df["organisation_name"] = df["organisation_name"].astype(str).str.strip()
df["main_code"]         = df["main_code"].astype(str).str.strip()
df["sub_code"]          = df["sub_code"].astype(str).str.strip()
```

### Step D — Filter CY only (halves row count)
```python
def infer_year_type(main_code: str) -> str:
    return "PY" if "PY" in str(main_code) else "CY"

df["year_type"] = df["main_code"].apply(infer_year_type)
df = df[df["year_type"] == "CY"].copy()
# NHS Trusts file: ~481K → ~241K rows
# Foundation Trusts file: ~1.1M → ~550K rows
```

### Step E — Cast Total + attach metadata columns
```python
df["total"]          = pd.to_numeric(df["total"], errors="coerce").fillna(0).astype("int64")
df["source_file"]    = source_file     # "TAC_NHS_trusts_2023-24.xlsx"
df["trust_type"]     = trust_type      # "NHS_TRUST" or "FOUNDATION_TRUST"
df["financial_year"] = financial_year  # "2023/24"
```

---

## 5. `validate()` — Stop Before Writing Bad Data

Three checks with two severity levels:

```python
# CRITICAL — raises exception, halts pipeline
for col in ["organisation_name", "sub_code", "total", "financial_year"]:
    nulls = data_df[col].isna().sum()
    if nulls:
        errors.append(f"[CRITICAL] {nulls} nulls in '{col}'")

# WARNING — logs and continues
dupes = data_df.duplicated(subset=["organisation_name", "main_code", "sub_code"]).sum()
unmatched = set(data_df["organisation_name"]) - set(provider_df["organisation_name"])
```

| Check | Severity | Reason |
|-------|----------|--------|
| Null in critical column | CRITICAL — stop | A null in `sub_code` means a row has no identity; cannot be loaded meaningfully |
| Duplicate rows | WARNING — continue | MySQL UPSERT handles duplicates anyway |
| Org name not in provider list | WARNING — continue | Those rows simply won't resolve an ODS code (dropped in the join) |

**Rule:** Halt on problems that cannot be recovered from. Warn on problems that can be handled downstream.

---

## 6. `load_staging()` — Write to nhs_stg

```python
# DELETE existing data for this year/type first (idempotent)
conn.execute(text(
    "DELETE FROM stg_tac_raw WHERE financial_year = :fy AND trust_type = :tt"
), {"fy": financial_year, "tt": trust_type})

# Then INSERT fresh data
data_df.to_sql("stg_tac_raw", engine, if_exists="append", index=False, chunksize=2000)
```

**Why DELETE before INSERT in staging?**
Staging is a buffer, not a permanent store. If you re-run the pipeline for the same year
(e.g. a corrected file), you want to replace old data, not accumulate duplicates.
DELETE is scoped to `(financial_year, trust_type)` — only removes the specific file being reloaded.

**Why `chunksize=2000`?**
pandas `to_sql()` builds one SQL INSERT per chunk. Without chunking, a 241K-row INSERT
exceeds MySQL's `max_allowed_packet` limit and crashes. At chunksize=2000: ~120 INSERT statements.

---

## 7. `populate_dim_trust()` — Slowly Changing Dimension

```python
INSERT INTO dim_trust (org_code, organisation_name, ...)
VALUES (...)
ON DUPLICATE KEY UPDATE
    last_year_seen = VALUES(last_year_seen),
    sector         = COALESCE(VALUES(sector), sector),
    updated_ts     = CURRENT_TIMESTAMP
```

This is a **Slowly Changing Dimension (SCD Type 1)** — overwrite, don't keep history.

Key behaviours:
- `last_year_seen` — always updated to the latest year processed
- `first_year_seen` — NOT in the UPDATE clause, so it keeps the earliest year (set only on first INSERT)
- `COALESCE(VALUES(sector), sector)` — if the new file has null sector, keep the old value

---

## 8. `promote_to_fact()` — The Critical Join

**Step A — Join staging + provider list to resolve org_code:**
```python
sql = """
    SELECT
        p.org_code,          -- resolved from name lookup
        r.financial_year,
        r.worksheet_name,
        r.main_code,
        r.sub_code,
        r.total AS total_000s,
        r.trust_type,
        r.source_file
    FROM stg_tac_raw r
    JOIN stg_provider_list p
        ON  r.organisation_name = p.organisation_name
        AND r.financial_year    = p.financial_year
        AND r.trust_type        = p.trust_type
    WHERE r.financial_year = %(fy)s
      AND r.trust_type     = %(tt)s
"""
```

The join is on 3 columns to uniquely match organisation name within the same year and file type.
Any name in `stg_tac_raw` that doesn't match `stg_provider_list` is silently dropped.
That is why `validate()` warns about unmatched names — they disappear here.

**Step B — UPSERT into fct_tac:**
```python
INSERT INTO fct_tac (org_code, financial_year, main_code, sub_code, total_000s, ...)
VALUES (...)
ON DUPLICATE KEY UPDATE
    total_000s  = VALUES(total_000s),
    load_ts     = CURRENT_TIMESTAMP
```

The UNIQUE KEY on `(org_code, financial_year, main_code, sub_code)` prevents duplicates.
On re-run: the existing row is updated, not duplicated. This makes the pipeline **idempotent**.

**Step C — Chunked writing (1,000 rows per chunk):**
```python
for start in range(0, len(fact_df), 1000):
    chunk = fact_df.iloc[start: start + 1000]
    conn.execute(upsert_sql, chunk.to_dict(orient="records"))
```

Uses parameterised SQL (not `to_sql()`) because `to_sql()` doesn't support `ON DUPLICATE KEY UPDATE`.

---

## Full Flow: One File, Start to Finish

```
TAC_NHS_foundation_trusts_2023-24.xlsx  (38MB, ~1.1M rows)
  │
  ├── filename_to_financial_year()  →  "2023/24"
  ├── filename_to_trust_type()      →  "FOUNDATION_TRUST"
  │
  ├── read_provider_list()
  │     140 rows (name → ODS code)  →  stg_provider_list
  │
  ├── read_all_data()
  │     1.1M rows read
  │     CY filter → ~550K rows
  │     Columns normalised, metadata attached
  │
  ├── validate()
  │     Null checks → pass
  │     Duplicate check → warn if any
  │     Name match check → warn if any
  │
  ├── load_staging()
  │     DELETE old (2023/24, FOUNDATION_TRUST) rows from staging
  │     INSERT 550K rows → nhs_stg.stg_tac_raw
  │     INSERT 140 rows → nhs_stg.stg_provider_list
  │
  ├── populate_dim_trust()
  │     UPSERT 140 trust records → nhs_finance.dim_trust
  │
  └── promote_to_fact()
        JOIN stg_tac_raw + stg_provider_list
        → 550K rows now have org_code
        UPSERT 550K rows → nhs_finance.fct_tac
```

After all 6 files: `fct_tac` = 2,179,740 rows. `dim_trust` = 206 rows.

---

## Stage 2 Summary

| Concept | The Design Decision | Why |
|---------|---------------------|-----|
| Filename parsing | Year + trust type from filename | The file itself has no trust_type column |
| `float` dtype for Total | NaN-safe read, then cast to int64 | NaN cannot exist in int columns |
| CY filter | Drop `"PY" in main_code` | Prevents double-counting across 6 files |
| Validate before write | Critical = halt; Warning = log | Catch unrecoverable problems early |
| DELETE + INSERT in staging | Scoped to `(year, trust_type)` | Idempotent re-runs without duplicates |
| JOIN in promote_to_fact | Only way to resolve name → ODS code | "All data" sheet has no org_code |
| UPSERT in fct_tac | `ON DUPLICATE KEY UPDATE` | Idempotent — safe to re-run anytime |
| chunksize | 2000 (staging), 1000 (fact) | Prevents MySQL max_allowed_packet crash |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [python/ingestion/load_tac_data.py](../python/ingestion/load_tac_data.py) | Full script — follow call chain top to bottom |
| [python/CLAUDE.md](../python/CLAUDE.md) | Coding standards: pandas style, chunking, logging, period key logic |

---

*Previous: [Stage 1 — Raw Source Data](stage_01_raw_source_data.md)*
*Next: [Stage 3 — Database Schema](stage_03_database_schema.md)*
