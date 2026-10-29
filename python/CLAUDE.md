# Python Layer — Pipeline Conventions

This describes the five scripts under `python/` — four pipeline stages plus one reference-data generator
(`build_subcode_reference.py`, not part of the daily pipeline).

## Environment

- Python 3.11+
- Install runtime dependencies with `pip install -r requirements.txt`
- Run focused regression tests with `python -m unittest discover -s tests -v`
- No linter is configured

## Directory Layout

```text
python/
├── ingestion/
│   ├── load_tac_data.py            # Excel → nhs_bronze → nhs_silver (dim_trust, fct_tac) — stages ③④
│   └── build_subcode_reference.py  # NHS illustrative TAC workbook → dim_subcode label seed (one-off, not in the pipeline)
├── transformation/
│   ├── transform_tac_data.py    # Enrichment: sector flags, YoY, income mix, sector benchmarks — stage ④
│   └── validate_tac_data.py     # 11 data-quality checks → data/processed/validation_report.csv — stage ④
└── reporting/
    └── export_for_powerbi.py    # nhs_gold views + nhs_silver dims → 13 CSVs in data/processed/powerbi_export/ — stage ⑤
```

## Database Connection

Every database script requires `DB_PASSWORD` from the environment. `DB_USER`, `DB_HOST`, and `DB_PORT`
also accept environment overrides and default to the local development values.

Since the schema split into three databases (`nhs_bronze`/`nhs_silver`/`nhs_gold`), each script also
defines which database(s) it primarily connects to and fully-qualifies the rest in its SQL text rather than
opening multiple engines per query — e.g. `export_for_powerbi.py` connects to `nhs_gold` (most of what it
exports are views) and writes `FROM nhs_silver.dim_trust` for the two dimension exports that need a table,
not a view.

```python
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
```

## Coding Style (as actually used in these four files)

- Functions, not classes — no script defines a class
- One function per pipeline step, named for what it does: `filename_to_financial_year()`,
  `promote_to_fact()`, `build_sector_benchmarks()`, `check_orphan_fact_rows()`
- `logging` module for all pipeline output (`log = logging.getLogger(__name__)`), never `print()`
- Every `_000s` column stays in £000s through every transform; conversion to £m happens only at the very
  edge — in DAX measures on import into Power BI, not in Python
- Docstring header at the top of every script (purpose, usage, expected inputs) — see any of the five files
  for the pattern

## Pandas Patterns Used Here

- `pd.read_excel(path, sheet_name=...)` for the two sheets that matter per workbook (`List of Providers`,
  `All data`) — see `find_sheet_name()` in `load_tac_data.py` for handling sheet-name drift across years
- Column-name normalisation via an explicit rename map for the 2021/22 files, which used different header
  text (`Organisation Name` with a space, `Value number`) than 2022/23 and 2023/24
- `engine.begin()` for scoped staging replacement and atomic fact-scope replacement
- deterministic provider-name keys plus reviewed aliases; unresolved mappings halt before writes
- SHA-256 import metadata in `nhs_bronze.import_batch`
- `CAST(... AS DOUBLE)` in export SQL so pandas receives numeric values without truncating genuine
  fractional £000 amounts stored as MySQL `DECIMAL(18,5)`
- `encoding="utf-8-sig"` on every `to_csv()` call in `export_for_powerbi.py` — the BOM is required for
  Excel/Power BI's CSV connector to read the `£` symbol correctly

## Validation Pattern

`validate_tac_data.py` runs a fixed set of named checks (`check_row_counts`, `check_no_duplicate_keys`,
`check_income_totals`, `check_ebitda_margin`, `check_orphan_fact_rows`, etc.), each calling a shared
`record(check_name, severity, passed, detail)` helper, then `write_report()` dumps every result to
`data/processed/validation_report.csv`. This mirrors the ten queries in `sql/views/v_validation_checks.sql`
— the SQL file is the version to run ad-hoc from a MySQL client; this script is the version that produces a
committable, timestamped artifact.

## Do Not

- Do not use `.iterrows()` for anything the pipeline currently does with a vectorised `pandas` operation or
  a scoped SQL `UPDATE`/`INSERT`
- Do not truncate the whole `fct_tac`; replace only the exact `(financial_year, trust_type)` scope being
  reloaded so stale rows cannot survive while other source files remain intact
- Do not silently drop rows in `validate()` — a critical failure must raise and stop the load before any
  write occurs
