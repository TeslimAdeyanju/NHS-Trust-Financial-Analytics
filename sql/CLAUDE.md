# SQL Layer — Standards and Conventions

This describes the schema actually built by `sql/schema/create_tables_mysql.sql`. See the top-level
`CLAUDE.md` for why this file (unlike the earlier version of it) is scoped to what's real, not a general
finance-schema template.

## Database Target

- Engine: **MySQL 8.0**, run locally at `127.0.0.1:3306`
- Two databases: `nhs_stg` (staging) and `nhs_finance` (analytics/star schema)
- `sql/schema/create_tables.sql` is a PostgreSQL equivalent kept as a reference/portability exercise — it is
  not what's deployed or queried by anything in `python/` or `power_bi/`

## Schema Layout

```text
nhs_stg.stg_tac_raw          # Raw "All data" sheet rows, ~1:1 with source files
nhs_stg.stg_provider_list    # Raw "List of Providers" sheet rows (name → ODS code lookup)
nhs_finance.dim_*            # dim_trust, dim_financial_year, dim_worksheet, dim_subcode
nhs_finance.fct_tac          # Single EAV-style fact table — see PROJECT_DOCUMENTATION.md, stage ④
nhs_finance.v_*              # Analytical views built on fct_tac
```

## Table Naming

| Layer      | Prefix  | Example                 |
|------------|---------|--------------------------|
| Staging    | `stg_`  | `stg_provider_list`     |
| Dimension  | `dim_`  | `dim_trust`              |
| Fact       | `fct_`  | `fct_tac`                |
| View       | `v_`    | `v_income_expenditure`  |

There are no `sp_` procedures anywhere in this project — every transformation is either a Python script or
a `CREATE OR REPLACE VIEW`.

## Core Tables (as actually built)

### `dim_trust`

```text
org_code            CHAR(3)       PRIMARY KEY   -- ODS code, e.g. 'R1H'
organisation_name   VARCHAR(300)
trust_type          VARCHAR(20)                 -- NHS_TRUST | FOUNDATION_TRUST (governance, not sector)
sector               VARCHAR(50)                -- Acute | Mental Health | Community | Ambulance | Specialist
region               VARCHAR(100)
is_foundation        TINYINT(1)
first_year_seen      CHAR(7)
last_year_seen       CHAR(7)
```

`trust_type` and `sector` are two different attributes, both real, both populated from NHS England's own
labels — don't conflate them. There is no `icb_code` anywhere in this schema.

### `dim_financial_year`

```text
financial_year      CHAR(7)       PRIMARY KEY   -- '2023/24'
start_date           DATE                        -- 1 April
end_date             DATE                        -- 31 March
year_label_short      CHAR(5)                    -- '23/24'
```

There is no monthly grain (`period_key`, `period_label`, M01–M12) anywhere in this project — TAC is an
**annual** return. Five years are seeded (2019/20–2023/24) even though only three (2021/22–2023/24) are
actually loaded with data, to leave room for older or newer years without a schema change.

### `dim_worksheet` and `dim_subcode`

`dim_worksheet` is seeded with 19 TAC schedules in the DDL (TAC02 SoCI through TAC29 Losses+SP), including
several this project doesn't otherwise pivot into a view (balance sheet, cash flow, equity schedules) —
seeded for completeness. The live table ends up with **30** rows, not 19: `promote_to_fact()` in
`load_tac_data.py` self-heals it at ingestion time with `INSERT IGNORE`, adding a placeholder row
(`category = 'OTHER'`) for any `worksheet_name` it encounters in the real data that wasn't pre-seeded. This
means the `worksheet_name → dim_worksheet` foreign key on `fct_tac` can never reject a row just because the
DDL author didn't happen to seed that schedule. `dim_subcode` carries one row per SubCode (59, all
statically seeded — no self-healing here) with its `worksheet_name` FK, `expected_sign`, and an
`analytics_category` (`PAY` / `NON_PAY` / `NON_PAY_EXCL_EBITDA`) that `v_expenditure_breakdown` groups on.

### `fct_tac`

```text
tac_id              BIGINT        PRIMARY KEY AUTO_INCREMENT
org_code            CHAR(3)       FK → dim_trust
financial_year      CHAR(7)       FK → dim_financial_year
worksheet_name      VARCHAR(50)   FK → dim_worksheet
table_id            SMALLINT
main_code           VARCHAR(20)
sub_code            VARCHAR(20)   -- unconstrained by design; joins to dim_subcode
total_000s          DECIMAL(14,0)
trust_type          VARCHAR(20)
source_file         VARCHAR(200)
UNIQUE KEY uq_tac (org_code, financial_year, main_code, sub_code)
```

One row per line item per trust per year — **not** one row per trust. Full rationale for the EAV shape, the
UPSERT pattern, and why `sub_code` stays unconstrained is in `PROJECT_DOCUMENTATION.md`, stage ④.

## View Standards

- Every view is `USE nhs_finance;` then `DROP VIEW IF EXISTS ...; CREATE VIEW ... AS`, defined identically
  in both `create_tables_mysql.sql` and its own file under `sql/views/` — the standalone file is canonical
  if the two ever drift
- Every view carries `org_code` and `financial_year` (or is explicitly aggregated past trust grain, like
  `v_kpis`'s sector-benchmark rollup)
- All monetary columns stay in £000s inside SQL — conversion to £m happens only in DAX on import
- Percentages are `ROUND(..., 1)` and guarded with `NULLIF()`/`COALESCE()` against divide-by-zero, not bare
  division

## Query Style

- CTEs (`WITH`) for multi-step logic
- `MAX(CASE WHEN sub_code = '...' THEN total_000s END)` is the standard pivot idiom — see
  `v_income_expenditure.sql` and `v_expenditure_breakdown.sql`
- Always alias table names in joins: `fct_tac r JOIN dim_trust t ON ...`
- `CAST(... AS SIGNED)` on `_000s` columns in any query destined for CSV export, so pandas doesn't read them
  back as `Decimal`

## Example View Pattern (real, from `v_income_expenditure.sql`)

```sql
USE nhs_finance;
DROP VIEW IF EXISTS v_income_expenditure;
CREATE VIEW v_income_expenditure AS
SELECT
    org_code,
    financial_year,
    MAX(CASE WHEN sub_code = 'SCI0100A' THEN total_000s END) AS patient_care_income_000s,
    MAX(CASE WHEN sub_code = 'SCI0110A' THEN total_000s END) AS other_income_000s,
    MAX(CASE WHEN sub_code = 'SCI0140A' THEN total_000s END) AS operating_surplus_000s,
    MAX(CASE WHEN sub_code = 'SCI0240'  THEN total_000s END) AS net_surplus_000s
FROM fct_tac
WHERE worksheet_name = 'TAC02 SoCI'
GROUP BY org_code, financial_year;
```

## Do Not

- Do not add a `budget_000s`, `data_type`, or `variance_pct` column anywhere — there is no budget/forecast
  data source in this project; TAC is actuals-only (see top-level `CLAUDE.md`)
- Do not TRUNCATE `fct_tac` or `dim_trust` — they accumulate across all six source files; only `stg_*`
  tables are safe to delete-and-reload per file
- Do not add a direct `sub_code` FK on `fct_tac` — that constraint is already correctly enforced one join
  away, on `dim_subcode` (2.18M rows smaller); see the FK write-up in `PROJECT_DOCUMENTATION.md`, stage ④
- Do not use `SELECT *` in a view definition
