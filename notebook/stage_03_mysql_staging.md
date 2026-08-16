# Stage ③ — MySQL Staging

> `nhs_bronze` — populated by `python/ingestion/load_tac_data.py`. This stage's only job is to get the
> Excel data into a queryable form with the *minimum* transformation applied. No joins, no pivoting, no
> business logic — a faithful, query-able landing zone for exactly what NHS England published.

---

## Why a Separate Staging Database

The project uses a three-database **medallion** split — Bronze (raw landing), Silver (conformed dims/fact,
see [stage ④](stage_04_mysql_analytics.md)), Gold (curated analytical views, also stage ④):

```sql
CREATE DATABASE IF NOT EXISTS nhs_bronze; -- staging (buffer) — this stage
CREATE DATABASE IF NOT EXISTS nhs_silver; -- conformed dims + fact — see stage ④
CREATE DATABASE IF NOT EXISTS nhs_gold;   -- analytical views — see stage ④
```

| `nhs_bronze`                                 | `nhs_silver` / `nhs_gold`                         |
|---------------------------------------------|--------------------------------------------------|
| Holds data exactly as it arrived            | Holds cleaned, conformed analytics data + views  |
| Safe to delete-and-reload at any time       | Never truncated — accumulates across all six files |
| No foreign keys — accepts anything           | Has foreign keys — enforces integrity            |
| Used only during ingestion                   | Used by views, exports, Power BI                 |

If a load looks wrong, `nhs_bronze` tells you whether the fault is in what NHS England published or in the
transformation logic that runs next — without needing to touch the analytics layers Power BI is reading
from. `nhs_gold`'s views are a separate database from the `nhs_silver` tables they read, so every view's
`FROM`/`JOIN` fully-qualifies its source (`FROM nhs_silver.fct_tac`) — MySQL views can query another
database on the same server natively, no cross-database tricks required.

---

## Reading the Workbook: `read_all_data()`, Five Steps

**Step A — Read the sheet, with explicit dtypes:**

```python
sheet_name = find_sheet_name(path, "All data")  # handles "All data" vs "All Data"
df = pd.read_excel(path, sheet_name=sheet_name, header=0, dtype={
    "OrganisationName": str,
    "WorkSheetName":    str,
    "TableID":          "Int64",   # nullable integer
    "MainCode":         str,
    "RowNumber":        "Int64",
    "SubCode":          str,
    "Total":            float,     # float first — NaN-safe, cast to int later
})
```

**Step B — Normalise column names** (the 2021/22-vs-later inconsistency from [stage ②](stage_02_raw_excel_files.md)):

```python
col_map = {
    "Organisation Name": "OrganisationName",
    "Value number":      "Total",
    "Value Number":      "Total",
}
df = df.rename(columns=col_map)
```

**Step C — Drop null rows, strip strings:**

```python
df = df.dropna(subset=["organisation_name", "sub_code", "total"])
df["organisation_name"] = df["organisation_name"].astype(str).str.strip()
```

**Step D — Filter CY only** (halves the row count):

```python
def infer_year_type(main_code: str) -> str:
    return "PY" if "PY" in str(main_code) else "CY"

df["year_type"] = df["main_code"].apply(infer_year_type)
df = df[df["year_type"] == "CY"].copy()
# NHS Trusts file:         ~481K → ~241K rows
# Foundation Trusts file: ~1.1M → ~550K rows
```

**Step E — Cast `Total`, attach filename-derived metadata:**

```python
df["total"]          = pd.to_numeric(df["total"], errors="coerce").fillna(0).astype("int64")
df["source_file"]    = source_file
df["trust_type"]     = trust_type
df["financial_year"] = financial_year
```

---

## `validate()` — Stop Before Writing Bad Data

Two severity levels, three checks:

| Check | Severity | Reason |
|-------|----------|--------|
| Null in a critical column (`organisation_name`, `sub_code`, `total`, `financial_year`) | CRITICAL — halts the load, raises before any write | A null `sub_code` means the row has no identity |
| Duplicate `(organisation_name, main_code, sub_code)` rows | WARNING — logs, continues | The UPSERT in stage ④ handles duplicates anyway |
| Organisation name not found in the provider list | WARNING — logs, continues | Those rows won't resolve an ODS code and are dropped at the stage ④ join |

**Rule:** halt on problems that cannot be recovered from downstream; warn on problems that can.

---

## `load_staging()` — Write to `nhs_bronze`

```python
# DELETE existing data for this year/type first (idempotent)
conn.execute(text(
    "DELETE FROM stg_tac_raw WHERE financial_year = :fy AND trust_type = :tt"
), {"fy": financial_year, "tt": trust_type})

# Then INSERT fresh data
data_df.to_sql("stg_tac_raw", engine, if_exists="append", index=False, chunksize=2000)
```

Staging is a buffer, not a permanent store — re-running the pipeline for a corrected file should replace
old data, not accumulate duplicates. The DELETE is scoped to `(financial_year, trust_type)`, so reloading
one file never touches another file's rows. `chunksize=2000` matters because pandas' `to_sql()` builds one
`INSERT` per chunk — without it, a 241K-row single INSERT exceeds MySQL's `max_allowed_packet` and the
load crashes.

---

## `stg_tac_raw` — The Staging Table

```sql
CREATE TABLE stg_tac_raw (
    id                BIGINT          AUTO_INCREMENT PRIMARY KEY,
    organisation_name VARCHAR(300)    NOT NULL,   -- name only — org_code isn't resolved yet
    worksheet_name    VARCHAR(50)     NOT NULL,
    table_id          SMALLINT        NOT NULL,
    main_code         VARCHAR(20)     NOT NULL,
    row_num           SMALLINT        NOT NULL,
    sub_code          VARCHAR(20)     NOT NULL,
    total             DECIMAL(14,0)   NOT NULL,   -- £000s
    source_file       VARCHAR(200)    NOT NULL,
    trust_type        VARCHAR(20)     NOT NULL,
    financial_year    CHAR(7)         NOT NULL,
    year_type         CHAR(2)         NOT NULL,   -- CY | PY
    load_ts           TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_stg_org_year  (organisation_name(100), financial_year),
    INDEX idx_stg_sub_code  (sub_code),
    INDEX idx_stg_year_type (financial_year, year_type)
) ENGINE=InnoDB;
```

- Uses `organisation_name`, not `org_code` — this is raw data, names not yet resolved to a stable key
- No `UNIQUE KEY` — staging accepts duplicate rows; deduplication happens at promotion, in stage ④
- `INDEX (organisation_name(100), ...)` — MySQL requires a prefix length on an index over a long `VARCHAR`

`stg_provider_list` is the same idea for the "List of Providers" sheet — a temporary, per-file lookup
(~639 rows across all six files combined) that stage ④'s join uses to resolve `organisation_name →
org_code`. Once that join runs, its job is done for that file. It carries a `trust_type` column
(`NHS_TRUST` | `FOUNDATION_TRUST`) alongside `financial_year`, so the join in stage ④ can match a name
within the same year *and* file type.

---

## Stage ③ Summary

| Concept | Design Decision | Why |
|---------|------------------|-----|
| Three databases | `nhs_bronze` buffer + `nhs_silver` conformed + `nhs_gold` views | Separates raw, clean, and curated; staging is safe to reload |
| `float` dtype for `Total` | NaN-safe read, cast to `int64` after filtering | `NaN` cannot exist in an integer column |
| CY filter | Drop rows where `main_code` contains `"PY"` | Prevents double-counting across six files |
| Validate before write | Critical → halt; Warning → log and continue | Catch unrecoverable problems before any row lands |
| DELETE + INSERT in staging | Scoped to `(financial_year, trust_type)` | Idempotent reloads without touching other files' rows |
| No FK, no UNIQUE KEY on `stg_tac_raw` | Staging accepts anything NHS England published | Integrity is enforced one stage later, in `fct_tac` |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [python/ingestion/load_tac_data.py](../python/ingestion/load_tac_data.py) | `read_provider_list()`, `read_all_data()`, `validate()`, `load_staging()` |
| [sql/schema/create_tables_mysql.sql](../sql/schema/create_tables_mysql.sql) | `stg_tac_raw` and `stg_provider_list` DDL |
| [python/CLAUDE.md](../python/CLAUDE.md) | Pandas patterns, hardcoded-connection rationale, validation pattern |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md), stage ③ | The narrative version, plus the client/server MySQL diagram |

---

*Previous: [Stage ② — Raw Excel Files](stage_02_raw_excel_files.md)*
*Next: [Stage ④ — MySQL Analytics](stage_04_mysql_analytics.md)*
