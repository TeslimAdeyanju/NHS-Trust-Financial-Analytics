# Stage 3 — Database Schema (Star Schema)

> The schema file (`sql/schema/create_tables_mysql.sql`) does everything in one script:
> creates both databases, defines all tables, seeds reference data, and creates all views.
> This stage covers structure only — views get their own stage.

---

## The Two-Database Architecture

```sql
CREATE DATABASE IF NOT EXISTS nhs_stg;     -- staging (buffer)
CREATE DATABASE IF NOT EXISTS nhs_finance; -- analytics (source of truth)
```

| `nhs_stg`                                     | `nhs_finance`                              |
|-----------------------------------------------|--------------------------------------------|
| Holds data exactly as it arrived              | Holds cleaned, conformed analytics data    |
| Safe to truncate and reload at any time       | Never directly written except via promotion |
| No foreign keys — accepts anything            | Has foreign keys — enforces integrity      |
| Used only during ingestion                    | Used by views, exports, Power BI           |

Think of `nhs_stg` as a loading dock. `nhs_finance` is the organised warehouse floor.

If something goes wrong during ingestion, you can inspect staging to find whether the
problem is in the source files or in the transformation logic.

---

## Staging Tables

### `stg_tac_raw` — Raw Facts (~2.18M rows when all 6 files loaded)

```sql
CREATE TABLE stg_tac_raw (
    id                BIGINT          AUTO_INCREMENT PRIMARY KEY,
    organisation_name VARCHAR(300)    NOT NULL,   -- NOT org_code — name only
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
    ...
    INDEX idx_stg_org_year  (organisation_name(100), financial_year),
    INDEX idx_stg_sub_code  (sub_code),
    INDEX idx_stg_year_type (financial_year, year_type)
)
```

Key points:
- Uses `organisation_name`, not `org_code` — this is raw data, names not yet resolved
- No UNIQUE KEY — staging accepts duplicate rows; deduplication happens at promotion
- `INDEX` on `organisation_name(100)` — MySQL requires a prefix length for long VARCHAR indexes

### `stg_provider_list` — Name→Code Lookup (~618 rows)

Temporary lookup loaded per file. The JOIN in `promote_to_fact()` uses it to resolve
`organisation_name → org_code`. After promotion, its job is done for that file.

---

## The Star Schema Shape

```
              dim_financial_year
              (5 rows, seeded)
                     │ FK: financial_year
                     │
dim_worksheet ───────┼──── fct_tac ──── dim_trust
(19 rows, seeded)    │   (2.18M rows)  (206 rows)
                     │
                   (dim_subcode used by views — no FK to fct_tac)
```

`fct_tac` is the centre. Everything radiates from it — this is the "star" in star schema.

---

## Dimension Tables

### `dim_trust` — 206 Rows

```sql
CREATE TABLE dim_trust (
    org_code          CHAR(3)       NOT NULL PRIMARY KEY,  -- always exactly 3 chars
    organisation_name VARCHAR(300)  NOT NULL,
    trust_type        VARCHAR(20)   NOT NULL,              -- NHS_TRUST | FOUNDATION_TRUST
    sector            VARCHAR(50),                         -- Acute | Mental Health | etc.
    region            VARCHAR(100),
    is_foundation     TINYINT(1)    NOT NULL DEFAULT 0,    -- MySQL boolean convention
    first_year_seen   CHAR(7),                             -- earliest year in dataset
    last_year_seen    CHAR(7),                             -- latest year in dataset
    updated_ts        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)
```

- `CHAR(3)` not `VARCHAR(3)` — ODS codes are always exactly 3 characters; CHAR is more efficient
- `is_foundation TINYINT(1)` — MySQL has no boolean type; `TINYINT(1)` is the convention
- `first_year_seen` is set on first INSERT and never updated — tracks when Trust first appeared
- `last_year_seen` is updated on every UPSERT — tracks when Trust was last seen
- `ON UPDATE CURRENT_TIMESTAMP` — automatically stamps when any field changes

### `dim_financial_year` — 5 Rows, Pre-seeded in DDL

```sql
INSERT INTO dim_financial_year VALUES
    ('2019/20', '2019-04-01', '2020-03-31', '19/20', 1),
    ('2020/21', '2020-04-01', '2021-03-31', '20/21', 1),
    ('2021/22', '2021-04-01', '2022-03-31', '21/22', 1),
    ('2022/23', '2022-04-01', '2023-03-31', '22/23', 1),
    ('2023/24', '2023-04-01', '2024-03-31', '23/24', 1);
```

**Why seeded in DDL, not loaded by Python?**
The NHS financial year calendar is fixed — 1 April to 31 March, forever.
Nothing to parse or infer. Hard-coding it is safer and simpler than loading from a file.

`year_label_short` (`'23/24'`) is for Power BI chart axis labels — `'2023/24'` is too long.

### `dim_worksheet` — 19 Rows, Pre-seeded

```sql
INSERT INTO dim_worksheet VALUES
    ('TAC02 SoCI',     'Statement of Comprehensive Income', 'SUMMARY',      'SCI'),
    ('TAC06 Op Inc 1', 'Operating Income from Patient Care','INCOME',       'INC0'),
    ('TAC08 Op Exp',   'Operating Expenditure',            'EXPENDITURE',   'EXP'),
    ('TAC09 Staff',    'Staff Costs and WTE Numbers',      'STAFF',         'STA'),
    ...
```

The `category` column (`SUMMARY`, `INCOME`, `EXPENDITURE`, `STAFF`, `BALANCE_SHEET`) groups
worksheets for filtering at the schedule-group level.

The `sub_code_prefix` (`'SCI'`, `'EXP'`, `'STA'`) documents which SubCodes belong to each worksheet.

### `dim_subcode` — 56 Rows, Pre-seeded (most important dimension)

```sql
CREATE TABLE dim_subcode (
    sub_code           VARCHAR(20)  NOT NULL PRIMARY KEY,
    worksheet_name     VARCHAR(50)  NOT NULL,
    description        VARCHAR(300) NOT NULL,
    expected_sign      CHAR(3),               -- '+' | '-' | '+/-'
    unit               VARCHAR(10)  DEFAULT '£000',
    is_subtotal        TINYINT(1)   NOT NULL DEFAULT 0,
    analytics_category VARCHAR(30),            -- PAY | NON_PAY | NON_PAY_EXCL_EBITDA | etc.
    FOREIGN KEY (worksheet_name) REFERENCES dim_worksheet(worksheet_name)
)
```

**`analytics_category`** — the most important column in the entire dimension layer.
Tags each SubCode so views can SUM by category without hardcoding SubCode lists:

| analytics_category     | What it includes                         | Used for              |
|------------------------|------------------------------------------|-----------------------|
| `PAY`                  | EXP0130 staff, EXP0300 R&D staff, etc.  | Pay % of income KPI   |
| `NON_PAY`              | Drugs, supplies, premises, negligence   | Non-pay breakdown     |
| `NON_PAY_EXCL_EBITDA`  | EXP0240 depreciation, EXP0250 amort     | Added back in EBITDA  |
| `PATIENT_INCOME`       | All TAC06 income lines                  | Income analysis       |
| `STAFF_WTE`            | STA03xx/STA0410 WTE lines               | Workforce analysis    |

The `v_expenditure_breakdown` view uses this:
```sql
SUM(CASE WHEN sc.analytics_category = 'PAY'                  THEN f.total_000s ELSE 0 END) AS pay_000s,
SUM(CASE WHEN sc.analytics_category = 'NON_PAY_EXCL_EBITDA' THEN f.total_000s ELSE 0 END) AS depreciation_amort_000s,
```

Without `analytics_category`, every view would need:
`WHERE sub_code IN ('EXP0130', 'EXP0140', 'EXP0300', 'EXP0320', 'EXP0350', ...)`.
Update one dimension record → every view benefits automatically.

**`is_subtotal`** — flags summary rows (e.g. `INC0350` = Total patient care income).
Detail exports exclude these (`WHERE is_subtotal = 0`) to prevent double-counting in Power BI.

**`expected_sign`** — documents whether the raw value should be positive, negative, or either.
Used for validation and documentation, not enforced by the schema.

---

## The Fact Table — `fct_tac` (2.18M rows)

```sql
CREATE TABLE fct_tac (
    tac_id          BIGINT        AUTO_INCREMENT PRIMARY KEY,
    org_code        CHAR(3)       NOT NULL,
    financial_year  CHAR(7)       NOT NULL,
    worksheet_name  VARCHAR(50)   NOT NULL,
    table_id        SMALLINT      NOT NULL,
    main_code       VARCHAR(20)   NOT NULL,
    sub_code        VARCHAR(20)   NOT NULL,
    total_000s      DECIMAL(14,0) NOT NULL,
    trust_type      VARCHAR(20)   NOT NULL,
    source_file     VARCHAR(200)  NOT NULL,
    load_ts         TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uq_tac (org_code, financial_year, main_code, sub_code),

    INDEX idx_fct_org_year  (org_code, financial_year),
    INDEX idx_fct_sub_code  (sub_code),
    INDEX idx_fct_worksheet (worksheet_name),
    INDEX idx_fct_year      (financial_year),

    FOREIGN KEY (org_code)       REFERENCES dim_trust(org_code),
    FOREIGN KEY (financial_year) REFERENCES dim_financial_year(financial_year),
    FOREIGN KEY (worksheet_name) REFERENCES dim_worksheet(worksheet_name)
)
```

### The UNIQUE KEY — Most Important Design Decision

```sql
UNIQUE KEY uq_tac (org_code, financial_year, main_code, sub_code)
```

This combination is the natural business key — one financial line for one Trust in one year
in one column of the original TAC spreadsheet.

Effect: `INSERT ... ON DUPLICATE KEY UPDATE` works correctly. Re-running the pipeline
**updates** existing rows rather than creating duplicates. Without this, every pipeline
run would add 2.18M new rows.

### The 4 Indexes — Covering the Main Query Patterns

| Index                   | Used when                                       |
|-------------------------|-------------------------------------------------|
| `(org_code, financial_year)` | "All data for Trust RFF in 2023/24" — most common filter |
| `(sub_code)`            | "SCI0100A for all Trusts" — used by every view pivot |
| `(worksheet_name)`      | "All TAC08 rows" — narrows before sub_code filter |
| `(financial_year)`      | "All 2023/24 data" — used in trend queries      |

### The 3 Foreign Keys

- `org_code → dim_trust` — can only load a fact row if the Trust exists in `dim_trust`
- `financial_year → dim_financial_year` — prevents loading data for an unknown year
- `worksheet_name → dim_worksheet` — every fact row must belong to a known TAC schedule

**Why NO FK from `fct_tac` to `dim_subcode`?**
`dim_subcode` seeds only 56 key SubCodes, but `fct_tac` contains thousands of distinct
SubCodes across all 19 TAC schedules. A full FK would block all non-seeded SubCodes from loading.

---

## Schema Execution Order (Dependency Chain)

```
1. CREATE DATABASE nhs_stg
2. stg_tac_raw          ← no FK deps
3. stg_provider_list    ← no FK deps

4. CREATE DATABASE nhs_finance
5. dim_financial_year   ← no FK deps  → seeded immediately
6. dim_worksheet        ← no FK deps  → seeded immediately
7. dim_subcode          ← FK → dim_worksheet  → seeded immediately
8. dim_trust            ← no FK deps (standalone PK)
9. fct_tac              ← FK → dim_trust, dim_financial_year, dim_worksheet

10. CREATE VIEW v_income_expenditure    ← reads fct_tac + dim_trust
11. CREATE VIEW v_expenditure_breakdown ← reads fct_tac + dim_trust + dim_subcode
12. CREATE VIEW v_workforce             ← reads fct_tac + dim_trust
13. CREATE VIEW v_kpis                  ← joins views 10 + 11 + 12
```

---

## Stage 3 Summary

| Concept | Design Decision | Why |
|---------|-----------------|-----|
| Two databases | `nhs_stg` buffer + `nhs_finance` analytics | Separation of raw from clean; safe to reload staging |
| `analytics_category` on dim_subcode | Tags each SubCode as PAY/NON_PAY/etc. | Views SUM by category without hardcoded SubCode lists |
| `is_subtotal` on dim_subcode | Flags summary/total rows | Excluded from detail exports to prevent double-counting |
| `UNIQUE KEY uq_tac` | 4-column natural business key on fct_tac | Makes pipeline idempotent via `ON DUPLICATE KEY UPDATE` |
| 4 indexes on fct_tac | Covers the main view query patterns | Fast execution on 2.18M rows |
| No FK to dim_subcode | Only 56 of thousands of SubCodes are seeded | A full FK would block all non-seeded SubCodes |
| Dims pre-seeded in DDL | Calendar, worksheets, subcode categories | Reference data is static — safer than loading from files |

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [sql/schema/create_tables_mysql.sql](../sql/schema/create_tables_mysql.sql) | Full schema — read in sections: staging → dims → fact → views |
| [sql/CLAUDE.md](../sql/CLAUDE.md) | SQL coding standards: naming, view patterns, CTE style |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md) §5–6 | Star schema diagram + two-database rationale |

---

*Previous: [Stage 2 — Python Ingestion Pipeline](stage_02_python_ingestion.md)*
*Next: [Stage 4 — SQL Analytical Views](stage_04_sql_views.md)*
