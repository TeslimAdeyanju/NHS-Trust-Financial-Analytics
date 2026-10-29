# Stage 3: Data Cleaning & Transformation

**Implementation:** Quality checks, source standardisation and conforming into Silver dimensions/facts.

> `nhs_bronze` — populated by `python/ingestion/load_tac_data.py`. This stage's only job is to get the
> Excel data into a queryable form with the *minimum* transformation applied. No joins, no pivoting, no
> business logic — a faithful, query-able landing zone for exactly what NHS England published.

---

## Statement-aware cleaning and quality controls

The TAC illustrative reporting template distinguishes three core statements: **TAC02 SoCI** (income and comprehensive income), **TAC03 SoFP** (financial position) and **TAC05 SoCF** (cash flows). The warehouse should preserve `worksheet_name`, `main_code`, `sub_code`, reporting year, original signed amount and source filename at the financial-fact grain.

### Cleaning rules before Silver promotion

1. **Source and worksheet identity:** Validate the sheet identifiers and expected source columns for each reporting year. Do not assume every template version has identical layouts.
2. **Current-year/prior-year separation:** Confirm the extraction of `CY` and `PY` from MainCode before filtering current-year data. Keep comparable periods distinct to avoid duplicate years.
3. **Accounting sign:** Store expenses, liabilities and cash outflows as signed source amounts. Invert them only in explicitly named presentation measures where needed.
4. **Subtotals:** Mark statement totals and intermediate subtotal codes. Never aggregate them together with their constituent detail rows.
5. **Completeness:** Distinguish missing values and unreported statement lines from genuine zeros; verify availability of SoCI, SoFP and SoCF for each provider/year.
6. **Business grain:** Detect duplicate `org_code + financial_year + worksheet_name + main_code + sub_code` records before pivoting with MAX. Investigate source keys before deduplicating.
7. **Provider population:** Match ODS identifiers and confirm changes in the published annual population rather than presuming a constant provider count.
8. **Reconciliation:** After Gold views are created, evaluate `sql/views/v_statement_reconciliation.sql` and investigate non-zero residuals and nulls.

These controls were exercised in the fresh six-workbook run. Every source gate passed with zero duplicate
source rows, zero proposed fact-key collisions, zero duplicate or ambiguous provider mappings and zero
unmatched populated CY rows. The illustrative workbook remains reference metadata rather than a fact
source and is intentionally excluded from ingestion.

Related implementation: [TAC schema](../../sql/schema/create_tables_mysql.sql), [validation script](../../python/transformation/validate_tac_data.py), [reconciliation SQL](../../sql/views/v_statement_reconciliation.sql).

---


## Why a Separate Staging Database

The project uses a three-database **medallion** split — Bronze (raw landing), Silver (conformed dims/fact,
see [stage ④](../04-data-modelling-and-analytics/README.md)), Gold (curated analytical views, also stage ④):

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
    "Total":            float,     # NaN-safe; rounded to five source decimals later
})
```

**Step B — Normalise column names** (the 2021/22-vs-later inconsistency from [stage ②](../02-data-ingestion/README.md)):

```python
col_map = {
    "Organisation Name": "OrganisationName",
    "Value number":      "Total",
    "Value Number":      "Total",
}
df = df.rename(columns=col_map)
```

**Step C — Require identifying fields, preserve blank amounts, and strip strings:**

```python
df = df.dropna(subset=["organisation_name", "worksheet_name", "main_code", "sub_code"])
df["organisation_name"] = df["organisation_name"].astype(str).str.strip()
```

**Step D — Classify CY/PY without discarding either from Bronze:**

```python
def infer_year_type(main_code: str) -> str:
    return "PY" if "PY" in str(main_code) else "CY"

df["year_type"] = df["main_code"].apply(infer_year_type)
# Silver promotion later selects year_type = "CY".
```

**Step E — Cast `Total`, attach filename-derived metadata:**

```python
df["total"]          = pd.to_numeric(df["total"], errors="coerce").round(5)
df["provider_name_key"] = df["organisation_name"].map(provider_name_key)
df["source_file"]    = source_file
df["source_sha256"]  = source_sha256
df["trust_type"]     = trust_type
df["financial_year"] = financial_year
```

---

## `validate()` — Stop Before Writing Bad Data

The source gate runs before any staging or fact write:

| Check | Severity | Reason |
|-------|----------|--------|
| Null in an identifying field | CRITICAL — halts the load | The source row cannot be traced safely |
| Duplicate full source-grain rows | CRITICAL — halts the load | An upsert must not conceal source duplication |
| Duplicate proposed fact-key rows | CRITICAL — halts the load | Two source lines must not collide at the Silver unique key |
| Duplicate provider lookup rows | CRITICAL — halts the load | The provider join must remain one-to-one |
| Normalised provider key maps to multiple ODS codes | CRITICAL — halts the load | The mapping is ambiguous |
| Populated CY row has no provider mapping | CRITICAL — halts the load | Financial rows must never disappear at the ODS join |

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
    total             DECIMAL(18,5),              -- £000s; preserves fractional source values and blanks
    provider_name_key VARCHAR(300)    NOT NULL,
    source_file       VARCHAR(200)    NOT NULL,
    source_sha256     CHAR(64)        NOT NULL,
    trust_type        VARCHAR(20)     NOT NULL,
    financial_year    CHAR(7)         NOT NULL,
    year_type         CHAR(2)         NOT NULL,   -- CY | PY
    load_ts           TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_stg_org_year  (organisation_name(100), financial_year),
    INDEX idx_stg_sub_code  (sub_code),
    INDEX idx_stg_year_type (financial_year, year_type)
) ENGINE=InnoDB;
```

- Retains the published name and a deterministic normalised key; ODS resolution happens at promotion
- No `UNIQUE KEY` — staging preserves source evidence, but validation rejects duplicates before writing
- `INDEX (organisation_name(100), ...)` — MySQL requires a prefix length on an index over a long `VARCHAR`

`stg_provider_list` is the same idea for the "List of Providers" sheet — a per-file lookup that resolves
the normalised provider key to `org_code`. Punctuation and case differences are normalised; genuine name
changes use a small reviewed alias map. Fuzzy matching is not used. It carries a `trust_type` column
(`NHS_TRUST` | `FOUNDATION_TRUST`) alongside `financial_year`, so the join in stage ④ can match a name
within the same year *and* file type.

---

## Stage ③ Summary

| Concept | Design Decision | Why |
|---------|------------------|-----|
| Three databases | `nhs_bronze` buffer + `nhs_silver` conformed + `nhs_gold` views | Separates raw, clean, and curated; staging is safe to reload |
| `float` dtype for `Total` | NaN-safe read, then round to five decimals | Preserves 131,858 genuine fractional £000 amounts |
| CY/PY classification | Preserve both in Bronze; promote populated CY rows only | Retains source evidence while preventing double-counting in Silver |
| Validate before write | Critical → halt; Warning → log and continue | Catch unrecoverable problems before any row lands |
| DELETE + INSERT in staging | Scoped to `(financial_year, trust_type)` | Idempotent reloads without touching other files' rows |
| No FK, no UNIQUE KEY on `stg_tac_raw` | Staging accepts anything NHS England published | Integrity is enforced one stage later, in `fct_tac` |

## Verified validation results — 29 October 2026

The completed run produced 2,210,974 Silver facts and 215 trust dimension rows. The post-load validation
report recorded **18 passed checks, one non-critical warning and zero critical failures**:

- all three expected financial years were present;
- no null organisation codes, duplicate fact keys or orphan provider codes were found;
- 2023/24 total income was £129.2bn;
- 124 trusts met the project's operating-deficit definition in 2023/24;
- average 2023/24 EBITDA margin was 3.6%;
- average acute-sector pay-to-income was 64.9%;
- all 633 trust-years contained SoCI, SoFP and SoCF records;
- SoCI, SoFP and SoCF internal residuals were within £1k;
- four SoFP-to-SoCF closing-cash differences exceeded £1k and remain visible as a warning.

The machine-readable result is written to `data/processed/validation_report.csv`. A passed rule confirms
that rule only; it does not replace the outstanding bridge to NHS England's official
before-impairments-and-transfers measure.

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [python/ingestion/load_tac_data.py](../../python/ingestion/load_tac_data.py) | `read_provider_list()`, `read_all_data()`, `validate()`, `load_staging()` |
| [sql/schema/create_tables_mysql.sql](../../sql/schema/create_tables_mysql.sql) | `stg_tac_raw` and `stg_provider_list` DDL |
| [python/CLAUDE.md](../../python/CLAUDE.md) | Pandas patterns, environment-based connection configuration, validation pattern |
| [PROJECT_DOCUMENTATION.md](../../PROJECT_DOCUMENTATION.md), stage ③ | The narrative version, plus the client/server MySQL diagram |

---

*Previous: [Stage ② — Raw Excel Files](../02-data-ingestion/README.md)*
*Next: [Stage ④ — MySQL Analytics](../04-data-modelling-and-analytics/README.md)*
