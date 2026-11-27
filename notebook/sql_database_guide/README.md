# SQL Guide: How the Database Is Built

**Implementation:** The MySQL schema script, the Bronze, Silver and Gold structures it creates, and the
Gold views.

> The stage pages explain what Python does with the data. This page explains the SQL: what
> `create_tables_mysql.sql` builds, in what order and why, what each table is for, and how the Gold views
> work. It's a reference for the database itself, so it isn't tied to a single stage.

---

## Where SQL Fits

The pipeline has two halves, and they run at different times:

| Half | File | What it does | When it runs |
|------|------|--------------|--------------|
| **SQL builds the structure** | [`sql/schema/create_tables_mysql.sql`](../../sql/schema/create_tables_mysql.sql) | Creates the three databases, every table (empty, or seeded with reference rows) and every view | Once, before the first load, or whenever the schema changes |
| **Python fills it** | [`python/ingestion/load_tac_data.py`](../../python/ingestion/load_tac_data.py) | Reads each workbook, cleans and checks it, then writes rows into the tables SQL created | Every time the data is loaded or reloaded |

Python never creates a table. If the schema hasn't been built, the loader fails on its first write. A simple
way to explain it is that SQL builds the empty filing cabinet and labels the drawers, and Python files the
papers into those drawers. How Python connects and what it writes is covered in
[stage ③](../03_data_cleaning_and_transformation/README.md#how-python-and-sql-work-together) (Bronze) and
[stage ④](../04_data_modelling_and_analytics/README.md#how-python-fills-silver-once-per-workbook) (Silver).

## The SQL Files

| File | What it is | How it's used |
|------|------------|---------------|
| [`sql/schema/create_tables_mysql.sql`](../../sql/schema/create_tables_mysql.sql) | The full schema: databases, every table, the seeded reference rows | Run once to build everything |
| [`sql/schema/deploy_gold_views.sql`](../../sql/schema/deploy_gold_views.sql) | Runs the nine view files in the right order | Called at the end of the schema script, or run alone to rebuild the views |
| [`sql/views/v_*.sql`](../../sql/views/) | One file per Gold view: the canonical definitions | Run by `deploy_gold_views.sql` |
| [`sql/views/v_validation_checks.sql`](../../sql/views/v_validation_checks.sql) | Ad-hoc data checks, despite its `v_` name. It creates no view | Run by hand after a load |
| [`sql/analysis/*.sql`](../../sql/analysis/) | Ready-to-run benchmarking and trend queries against `nhs_gold` | Run by hand for analysis |

## Building the Schema

The schema is built with one command, run from the repository root:

```bash
mysql --commands -u root -p < sql/schema/create_tables_mysql.sql
```

`mysql` is MySQL's command-line client. `<` feeds it the file, and it runs every statement from top to
bottom. `--commands` is needed on MySQL 9 and later, because the file's last line (`SOURCE ...`) is a client
command that MySQL 9 otherwise skips. **The script drops and recreates every table, so running it again
deletes all loaded data.** It is a setup step, not part of a routine reload.

The script runs in this order:

| # | Statement | What it creates | Section |
|---|-----------|-----------------|---------|
| 1 | `CREATE DATABASE IF NOT EXISTS nhs_bronze / nhs_silver / nhs_gold` | Three empty databases, using `utf8mb4` so names such as *King’s* keep their characters | — |
| 2 | `USE nhs_bronze;` then `CREATE TABLE` ×3 | `import_batch`, `stg_tac_raw`, `stg_provider_list`, all empty | [Bronze](#bronze-the-landing-tables) |
| 3 | `USE nhs_silver;` then the four dimension tables | `dim_trust` (empty) and `dim_financial_year`, `dim_worksheet`, `dim_subcode` (seeded by `INSERT`) | [Silver](#silver-the-star-schema) |
| 4 | `CREATE TABLE fct_tac` | The fact table, empty, with its foreign keys to the dimensions | [Silver](#silver-the-star-schema) |
| 5 | `USE nhs_gold;` then `CREATE VIEW ...`, ending with `SOURCE sql/schema/deploy_gold_views.sql;` | The nine analytical views | [Gold](#gold-the-views) |

`DROP TABLE IF EXISTS` before each `CREATE TABLE` makes the script safe to re-run on a database that
already has the tables, at the cost of the data in them.

---

## Bronze: the Landing Tables

Each Bronze table has one job:

| Table | One row per | Written by (Python file → function) | Purpose |
|-------|-------------|-------------------------------------|---------|
| `import_batch` | Source file (by name and fingerprint) | [`load_tac_data.py`](../../python/ingestion/load_tac_data.py) → `record_import_batch()` | The audit log: which file was loaded, when, its row counts and gate results, and whether it succeeded |
| `stg_provider_list` | Trust in a workbook's "List of Providers" sheet | [`load_tac_data.py`](../../python/ingestion/load_tac_data.py) → `load_staging()` | The lookup that turns a trust name into its ODS code |
| `stg_tac_raw` | Line in a workbook's "All data" sheet | [`load_tac_data.py`](../../python/ingestion/load_tac_data.py) → `load_staging()` | The near-verbatim copy of every published figure, current and prior year |

**`import_batch`**, the audit log:

```sql
CREATE TABLE import_batch (
    import_id               BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    source_file             VARCHAR(200)  NOT NULL,   -- e.g. TAC_NHS_trusts_2023-24.xlsx
    source_sha256           CHAR(64)      NOT NULL,   -- fingerprint of the file's exact bytes
    file_size_bytes         BIGINT        NOT NULL,
    financial_year          CHAR(7)       NOT NULL,
    trust_type              VARCHAR(20)   NOT NULL,

    -- Counts calculated by the quality gate
    source_rows             BIGINT,
    current_year_rows       BIGINT,
    fact_candidate_rows     BIGINT,
    provider_rows           INT,
    duplicate_rows          BIGINT,
    duplicate_fact_key_rows BIGINT,
    unmatched_provider_rows BIGINT,
    ambiguous_provider_keys INT,
    duplicate_provider_rows INT,

    status                  VARCHAR(20)   NOT NULL,   -- STARTED | VALIDATED | LOADED | FAILED
    error_message           VARCHAR(1000),            -- why it FAILED
    started_ts              TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    completed_ts            TIMESTAMP     NULL,

    UNIQUE KEY uq_import_batch (source_file, source_sha256),   -- one row per file version
    INDEX idx_import_scope (financial_year, trust_type, status)
) ENGINE=InnoDB;
```

The unique key on `(source_file, source_sha256)` decides what counts as "the same load". Python writes to
this table with `INSERT ... ON DUPLICATE KEY UPDATE`, so reloading an unchanged file updates its existing
row. A corrected file has a different fingerprint, so it gets a new row, and the history of both versions
is kept.

**`stg_tac_raw`**, the published figures:

```sql
CREATE TABLE stg_tac_raw (
    id                 BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,

    -- The source row, as published
    organisation_name  VARCHAR(300)  NOT NULL,   -- ODS code is attached later, in Silver
    worksheet_name     VARCHAR(50)   NOT NULL,
    table_id           SMALLINT      NOT NULL,
    main_code          VARCHAR(20)   NOT NULL,
    row_num            SMALLINT      NOT NULL,
    sub_code           VARCHAR(20)   NOT NULL,
    total              DECIMAL(18,5),            -- £000s; NULL means a blank amount

    -- Added by the Python loader
    provider_name_key  VARCHAR(300)  NOT NULL,   -- normalised name, used for matching
    source_file        VARCHAR(200)  NOT NULL,
    source_sha256      CHAR(64)      NOT NULL,
    trust_type         VARCHAR(20)   NOT NULL,   -- NHS_TRUST | FOUNDATION_TRUST
    financial_year     CHAR(7)       NOT NULL,   -- e.g. 2023/24
    year_type          CHAR(2)       NOT NULL,   -- CY or PY
    load_ts            TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    -- Indexes for the joins and filters used when promoting to Silver
    INDEX idx_stg_org_year      (organisation_name(100), financial_year),
    INDEX idx_stg_provider_key  (provider_name_key(100), financial_year, trust_type),
    INDEX idx_stg_sub_code      (sub_code),
    INDEX idx_stg_year_type     (financial_year, year_type)
) ENGINE=InnoDB;
```

It has no unique key on purpose: Bronze is a record of what was published, and duplicates are stopped by
the quality gate in Python before they can be written. `total` allows `NULL` so a blank amount stays
distinct from a genuine zero, and `DECIMAL(18,5)` keeps the source's five decimal places.

**`stg_provider_list`**, the name-to-code lookup:

```sql
CREATE TABLE stg_provider_list (
    id                 INT           NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organisation_name  VARCHAR(300)  NOT NULL,   -- as published
    org_code           CHAR(3)       NOT NULL,   -- the ODS code, e.g. RCF
    region             VARCHAR(100),
    sector             VARCHAR(50),              -- Acute, Mental Health, ...
    comments           TEXT,
    provider_name_key  VARCHAR(300)  NOT NULL,   -- same normalised key as stg_tac_raw
    source_file        VARCHAR(200)  NOT NULL,
    source_sha256      CHAR(64)      NOT NULL,
    trust_type         VARCHAR(20)   NOT NULL,
    financial_year     CHAR(7)       NOT NULL,
    load_ts            TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_prov_org_code (org_code),
    INDEX idx_prov_name     (organisation_name(100)),
    INDEX idx_prov_key      (provider_name_key(100), financial_year, trust_type)
) ENGINE=InnoDB;
```

It shares `provider_name_key`, `financial_year` and `trust_type` with `stg_tac_raw`, which are exactly the
three columns the Silver promotion joins on. `idx_stg_provider_key` and `idx_prov_key` index those columns
so the join is fast.

Two details apply to every Bronze table:

- **`financial_year` and `trust_type` are on every row.** Together they identify which of the six
  workbooks a row came from, so a reload can delete and replace exactly one file's rows.
- **`organisation_name(100)` in an index** means "index the first 100 characters". MySQL limits the size of
  an index entry, and 100 characters is enough to tell trust names apart.

---

## Silver: the Star Schema

The script switches to Silver with `USE nhs_silver;` and runs these steps in order:

| # | Statement | What it creates | Filled by |
|---|-----------|-----------------|-----------|
| 1 | `DROP TABLE IF EXISTS fct_tac; DROP TABLE IF EXISTS dim_subcode;` | Nothing. It clears the two tables that hold foreign keys first, because MySQL won't drop a table another table still points to | — |
| 2 | `CREATE TABLE dim_trust` | One row per trust (ODS code). **Created empty** | Python: `populate_dim_trust()` |
| 3 | `CREATE TABLE dim_financial_year` + `INSERT` | The five years 2019/20 to 2023/24, with their 1 April and 31 March dates. Seeded wider than the data so new years need no schema change | SQL only |
| 4 | `CREATE TABLE dim_worksheet` + `INSERT` | The 28 TAC schedules (`TAC02 SoCI` ... `TAC29 Losses+SP`), each with a title and category such as `BALANCE_SHEET` | SQL, plus Python adds any schedule that's missing |
| 5 | `CREATE TABLE dim_subcode` + `INSERT` | About 1,000 SubCode labels. 59 are hand-written with an `analytics_category` (`PAY`, `NON_PAY` ...). The rest were generated from NHS England's illustrative workbook by `build_subcode_reference.py` | SQL only |
| 6 | `CREATE TABLE fct_tac` | The fact table, **created empty**, with a unique key and three foreign keys | Python: `promote_to_fact()` |

**The order is forced by the foreign keys.** A foreign key is a rule that a value must already exist in
another table: `fct_tac.org_code` must be a row in `dim_trust`, `fct_tac.financial_year` a row in
`dim_financial_year`, and `fct_tac.worksheet_name` a row in `dim_worksheet`. `dim_subcode.worksheet_name`
must likewise exist in `dim_worksheet`. MySQL can only create a foreign key to a table that already exists,
so the dimensions come first and the fact table last. The same rule means Python must write `dim_trust`
before `fct_tac` on every load.

**Some tables are filled by SQL and some by Python**, depending on where their data comes from.
`dim_financial_year`, `dim_worksheet` and `dim_subcode` are **reference data**: they describe the TAC form
itself, which is the same for every trust, so they are written once into the schema. `dim_trust` and
`fct_tac` come from the workbooks, so Python fills them.

**`fct_tac` is long, not wide.** It has one row per trust, year and SubCode (for example, one row for
patient care income and another for total pay costs), because that is the shape NHS England publishes:

```sql
CREATE TABLE fct_tac (
    tac_id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    org_code        CHAR(3)       NOT NULL,
    financial_year  CHAR(7)       NOT NULL,
    worksheet_name  VARCHAR(50)   NOT NULL,
    table_id        SMALLINT      NOT NULL,
    main_code       VARCHAR(20)   NOT NULL,
    sub_code        VARCHAR(20)   NOT NULL,
    total_000s      DECIMAL(18,5) NOT NULL,
    trust_type      VARCHAR(20)   NOT NULL,
    source_file     VARCHAR(200)  NOT NULL,
    source_sha256   CHAR(64)      NOT NULL,
    load_ts         TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_tac (org_code, financial_year, main_code, sub_code),   -- no figure twice
    INDEX idx_fct_org_year  (org_code, financial_year),
    INDEX idx_fct_sub_code  (sub_code),
    INDEX idx_fct_worksheet (worksheet_name),
    INDEX idx_fct_year      (financial_year),
    FOREIGN KEY (org_code)       REFERENCES dim_trust(org_code),
    FOREIGN KEY (financial_year) REFERENCES dim_financial_year(financial_year),
    FOREIGN KEY (worksheet_name) REFERENCES dim_worksheet(worksheet_name)
) ENGINE=InnoDB;
```

`total_000s` is `NOT NULL` here, unlike `stg_tac_raw.total`, because blank amounts stay in Bronze and only
populated figures are promoted. Why `sub_code` has no foreign key, and the full design of every dimension,
is covered in [stage ④, The Star Schema](../04_data_modelling_and_analytics/README.md#the-star-schema).

---

## Gold: the Views

After Silver, the script runs `USE nhs_gold;` and creates the views. Its last line is:

```sql
SOURCE sql/schema/deploy_gold_views.sql;
```

`SOURCE` tells the `mysql` client to run another file. `deploy_gold_views.sql` runs the nine standalone
files in [`sql/views/`](../../sql/views/), which are the canonical definitions, so they replace the older
copies embedded earlier in the schema file. Each view file follows the same pattern:

```sql
USE nhs_gold;
DROP VIEW IF EXISTS v_income_expenditure;
CREATE VIEW v_income_expenditure AS
SELECT
    t.org_code,
    t.organisation_name,
    f.financial_year,
    MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END) AS patient_care_income_000s,
    ...
FROM nhs_silver.fct_tac f                          -- Silver table, named with its database
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC02 SoCI'
GROUP BY ...
```

Two things to explain about this pattern:

- **`nhs_silver.fct_tac`** names the database as well as the table, because the view lives in `nhs_gold`
  and its data lives in `nhs_silver`. MySQL allows a view to read another database on the same server.
- **`MAX(CASE WHEN sub_code = ... THEN total_000s END)`** is the pivot. It turns the long rows of
  `fct_tac` (one per SubCode) into named columns (one row per trust per year). `GROUP BY` collapses the
  rows, and `MAX` picks the one value that matches each SubCode.

**A view stores only the `SELECT`, not its result.** When a view is queried, MySQL runs that `SELECT`
against whatever is in Silver at that moment. That is why Gold never needs loading: once Python has
refreshed `fct_tac`, every view reflects it immediately. It is also why the views can be rebuilt at any time
without touching data:

```bash
mysql --commands -u root -p < sql/schema/deploy_gold_views.sql
```

The deploy order matters because some views read other views, and a view must exist before another view
can read it:

| Order | View | Reads from |
|------:|------|------------|
| 1 | `v_income_expenditure` | `fct_tac` (`TAC02 SoCI`) + `dim_trust` |
| 2 | `v_profit_and_loss` | `fct_tac` (`TAC02 SoCI`) + `dim_trust` |
| 3 | `v_balance_sheet` | `fct_tac` (`TAC03 SoFP`) + `dim_trust` |
| 4 | `v_cash_flow` | `fct_tac` (`TAC05 SoCF`) + `dim_trust` |
| 5 | `v_expenditure_breakdown` | `fct_tac` (`TAC08 Op Exp`) + `dim_trust` + `dim_subcode` |
| 6 | `v_workforce` | `fct_tac` (`TAC09 Staff`) + `dim_trust` |
| 7 | `v_kpis` | Views 1, 5 and 6 |
| 8 | `v_trust_annual_scorecard` | `v_kpis` + views 1, 5 and 6 + `fct_tac` |
| 9 | `v_statement_reconciliation` | Views 2, 3 and 4 + `fct_tac` (`TAC19 CCE`) |

![nhs_silver tables to nhs_gold views: fct_tac and dim_trust feed six views that read Silver directly (v_income_expenditure and v_profit_and_loss from TAC02 SoCI, v_balance_sheet from TAC03 SoFP, v_cash_flow from TAC05 SoCF, v_expenditure_breakdown from TAC08 Op Exp, v_workforce from TAC09 Staff); dim_subcode also feeds v_expenditure_breakdown. v_kpis reads v_income_expenditure, v_expenditure_breakdown and v_workforce. v_trust_annual_scorecard reads v_kpis and those three views. v_statement_reconciliation reads v_profit_and_loss, v_balance_sheet, v_cash_flow and fct_tac (TAC19 CCE). Views store no data; each is calculated from Silver when it is queried.](../../docs/images/gold_view_lineage.png)

What each view calculates, and the accounting behind it, is covered in
[stage ④, Analytics Layer](../04_data_modelling_and_analytics/README.md#analytics-layer--the-nine-sql-views).

### What happens when a view is read

For example, when `export_for_powerbi.py` connects to `nhs_gold` and runs `SELECT ... FROM v_kpis`:

1. MySQL opens the `v_kpis` definition and sees it needs `v_income_expenditure`, `v_expenditure_breakdown`
   and `v_workforce`.
2. Each of those runs its own `SELECT` on `nhs_silver.fct_tac`, filtered to its own schedule (`TAC02`,
   `TAC08`, `TAC09`), and pivots the long SubCode rows into one row per trust per year.
3. `v_kpis` joins the three results on `org_code` and `financial_year` and calculates the ratios (EBITDA
   margin, pay as a percentage of income ...).
4. The rows are returned to Python, which writes them to CSV for Power BI
   ([stage ⑤](../05_data_preparation_for_reporting/README.md)).

Nothing is stored along the way, so the KPIs always match the facts currently in Silver.

---

## Who Writes and Reads Each Table

| Database | Table / view | Created by | Written by | Read by |
|----------|--------------|------------|------------|---------|
| `nhs_bronze` | `import_batch` | Schema script | `record_import_batch()` | You, to audit loads |
| `nhs_bronze` | `stg_provider_list` | Schema script | `load_staging()` | `populate_dim_trust()`, `promote_to_fact()` |
| `nhs_bronze` | `stg_tac_raw` | Schema script | `load_staging()` | `promote_to_fact()` |
| `nhs_silver` | `dim_financial_year` | Schema script (seeded) | — | Foreign key on `fct_tac` |
| `nhs_silver` | `dim_worksheet` | Schema script (seeded) | `promote_to_fact()` adds missing schedules | Foreign keys on `fct_tac` and `dim_subcode` |
| `nhs_silver` | `dim_subcode` | Schema script (seeded) | — | `v_expenditure_breakdown`, `export_for_powerbi.py` |
| `nhs_silver` | `dim_trust` | Schema script (empty) | `populate_dim_trust()` | The Gold views, `export_for_powerbi.py` |
| `nhs_silver` | `fct_tac` | Schema script (empty) | `promote_to_fact()` | The Gold views, `export_for_powerbi.py`, `validate_tac_data.py` |
| `nhs_gold` | `v_*` (nine views) | `deploy_gold_views.sql` | — (views hold no data) | `transform_tac_data.py`, `validate_tac_data.py`, `export_for_powerbi.py`, `sql/analysis/` |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [sql/schema/create_tables_mysql.sql](../../sql/schema/create_tables_mysql.sql) | Every `CREATE DATABASE`, `CREATE TABLE` and seed `INSERT` |
| [sql/schema/deploy_gold_views.sql](../../sql/schema/deploy_gold_views.sql) | The view deploy order |
| [sql/views/](../../sql/views/) | One canonical file per Gold view |
| [sql/CLAUDE.md](../../sql/CLAUDE.md) | Naming conventions, view standards, query style |

---

*Python side: [Stage ③ — Data Cleaning & Transformation](../03_data_cleaning_and_transformation/README.md)
(Bronze) · [Stage ④ — Data Modelling & Analytics](../04_data_modelling_and_analytics/README.md) (Silver
and Gold)*
