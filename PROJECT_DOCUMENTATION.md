# NHS Trust Financial Analytics — Project Documentation

**Research-led financial analytics | NHS England provider accounts | 2021/22–2023/24**

This document explains the business question, NHS accounting context, implemented data architecture, six-stage processing lifecycle, analytical measures, published-account reconciliation and outstanding validation work. It is written for readers who want to understand **what the project does, why each design choice matters, how to reproduce it and which conclusions remain provisional**.

**Project status (28 October 2026):** The repository contains ingestion, transformation, SQL modelling, validation, export and Power BI modelling assets. The final interactive Power BI dashboard has **not been published**, and the project's historical financial totals have **not yet been independently reconciled** from the raw TAC workbooks to NHS England's consolidated accounts. Code and documentation are evidence of implementation, not proof of a successful fresh execution.

## Contents

### Part I — Background and Research Context

- [Research Question and Executive Summary](#research-question-and-executive-summary)
- [NHS Financial Reporting and Sustainability](#nhs-financial-reporting-and-sustainability)
- [Objectives, Scope and Definitions](#objectives-scope-and-definitions)

### Part II — Research Methodology

**Methodology: Six-Stage Data Analytics Lifecycle**

1. [Data Sourcing](#stage-1--data-sourcing) — obtain authoritative NHS England TAC data and define source controls.
2. [Data Ingestion](#stage-2--data-ingestion) — capture source workbooks and load raw records to Bronze.
3. [Data Cleaning & Transformation](#stage-3--data-cleaning--transformation) — standardise, validate and conform records in Silver.
4. [Data Modelling & Analytics](#stage-4--data-modelling--analytics) — organise dimensions, facts and financial KPIs in Silver and Gold.
5. [Data Preparation for Reporting](#stage-5--data-preparation-for-reporting) — prepare curated datasets and exports.
6. [Data Visualisation & Insights](#stage-6--data-visualisation--insights) — design and communicate Power BI financial analysis.

Detailed implementations remain in the stage-specific technical notebooks linked from each section.

### Part III — Findings, Validation and Project Outcomes

- [Financial Findings and Reconciliation](#financial-findings-and-reconciliation)
- [Data Quality, Auditability and Limitations](#data-quality-auditability-and-limitations)
- [Reproducibility and Operational Workflow](#reproducibility-and-operational-workflow)
- [Project Deliverables and Next Steps](#project-deliverables-and-next-steps)
- [Glossary and Reference Material](#glossary-and-reference-material)

---

# PART I — BACKGROUND AND RESEARCH CONTEXT

## Research Question and Executive Summary

### Why I undertook this project

NHS providers operate under persistent pressure to deliver safe and effective services while managing finite public resources. NHS England publishes Trust Accounts Consolidation (TAC) information that can help explain changes in provider income, operating expenditure, staffing costs and financial balances. However, the relevant information is spread across annual workbooks and accounting schedules, making systematic, cross-year exploration difficult without a repeatable analytical process.

I developed this project to connect **financial reporting knowledge, data engineering and business intelligence**. The intention is to make published financial data easier to analyse while retaining the accounting definitions and audit trails needed for trustworthy reporting.

### Research question

> **How is the financial health of NHS Trusts in England changing over time, and which parts of the health system are under the most pressure?**

This question has two parts: the national movement in financial performance, and the distribution of that performance across trusts, provider types and regions. National totals cannot, by themselves, identify the pressures experienced by each organisation or establish the causes of differences.

### What the external evidence currently shows

NHS England's published consolidated provider accounts report a surplus of **£562 million** in 2021/22, a deficit of **£457 million** in 2022/23 and a deficit of **£2.312 billion** in 2023/24, using the **surplus/(deficit) before impairments and transfers** measure. The associated number of providers reporting a deficit increased from **74 of 215** to **105 of 212** and **136 of 211** respectively.

These are **official published benchmarks, not independently reproduced outputs from the project's SQL pipeline**. The project also calculates an **operating** surplus/(deficit), which is a different measure; the earlier figures in project narratives must not be substituted for the official series or used to claim reconciliation. See [Financial reconciliation workpaper](reports/nhs_financial_reconciliation.md).

**Primary sources:** [2021/22 NHS provider accounts](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2021-to-2022), [2022/23 accounts](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2022-to-2023), [2023/24 accounts](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2023-to-2024).

### Analytical approach

The project uses Python to ingest and process NHS England TAC workbooks, MySQL to store and organise financial records, SQL to derive analytical views and KPIs, CSV exports to prepare curated reporting data, and Power BI/DAX assets to specify interactive reporting. Source accounting codes remain essential throughout: a polished chart is not an adequate substitute for a correctly defined financial measure.

---

## NHS Financial Reporting and Sustainability

### NHS providers and their financial context

NHS trusts and NHS foundation trusts deliver healthcare services within England's publicly funded health system. Provider activity includes acute, specialist, mental health, community and ambulance services; sector labels in source workbooks must be respected rather than inferred from a provider's name. Provider income, funding arrangements, patient-care costs and accounting treatment can vary, so benchmarking needs appropriate context.

NHS Trust Accounts Consolidation records include the **Statement of Comprehensive Income (SoCI)**, balance-sheet information and schedules for patient-care income, expenses and workforce. TAC is useful for consistent accounting analysis; it is not a substitute for operational, workforce-quality or clinical outcomes data.

### What financial sustainability means

For this project, financial sustainability means the capacity to meet obligations, manage resources and maintain safe healthcare delivery over time. **Covering annual costs is important but not sufficient**: liquidity, financial plans, cost pressures, productivity, capital commitments and continuity of patient services also matter.

The project evaluates complementary measures:

| Measure | Interpretation | Important qualification |
| --- | --- | --- |
| Operating surplus/(deficit) | Operating income less operating expenses | TAC `SCI0140A` in the current SQL; not the published adjusted balance |
| Before-impairments-and-transfers financial balance | NHS England's published provider financial comparison basis | Requires accounting reconciliation and consolidation adjustments |
| Net surplus/(deficit) | Bottom-line accounting result | Not necessarily the same as NHS England's published performance measure |
| EBITDA margin | Project-calculated operating result plus depreciation/amortisation, relative to income | Supplementary ratio; not cash flow or a regulatory pass/fail test |
| Pay as a percentage of income | Share of operating income used on workforce costs | Depends on consistent classification of staff and agency costs |
| Cost per WTE | Staff costs divided by average whole-time equivalent employees | Highly sensitive to workforce composition and cost definition |

**Regulatory distinction:** There is no substantiated NHS-wide rule in this repository that an EBITDA margin of 2% establishes financial sustainability or that a negative EBITDA margin automatically triggers regulatory intervention. NHS England uses a wider [oversight framework](https://www.england.nhs.uk/nhs-oversight-framework/) covering financial performance and other domains. Any RAG thresholds in this project are **illustrative, project-defined analytical bands** unless a separately cited official rule applies.

### Accounting comparability across years

Account balances can change because of service pressures **and** accounting policies. For example, NHS England reports that 2023/24 treatment of PFI and other service-concession liabilities under IFRS 16 increased the reported deficit by approximately **£1.094 billion**. The impact should be explained when discussing trends; it must not be applied automatically to an individual trust's unrelated operating measure.

---

## Objectives, Scope and Definitions

The objectives are to:

1. **Source and consolidate data** from published NHS Trust and Foundation Trust TAC workbooks for the three financial years, recording source versions and the actual population by year.
2. **Develop a reusable pipeline** for extraction, loading, data checks and repeatable transformation, with idempotence demonstrated by explicit reload tests rather than assumed.
3. **Calculate consistent financial indicators** and distinguish operating, net and adjusted balances.
4. **Reconcile relevant measures** to NHS England's published accounts, documenting consolidation adjustments and unexplained variances rather than forcing agreement.
5. **Keep calculations auditable** through source file, reporting year, trust identifier, worksheet, SubCode, data checks and transformation rules.
6. **Support financial interpretation and accessible reporting** through analytical SQL and a Power BI model, with dashboard publication as a pending deliverable.

### Scope

| Dimension | Definition |
| --- | --- |
| Reporting periods | 2021/22, 2022/23 and 2023/24 |
| Primary source | NHS England TAC workbooks: NHS trusts and foundation trusts for each year |
| Source format | Excel, provider roster and long-form TAC accounting records |
| Analytical grain | Primarily organisation × financial year, with source-level SubCode detail |
| Main technologies | Python, pandas, SQLAlchemy, MySQL, SQL, CSV and Power BI/DAX |
| Exclusions | No causal demonstration of why a trust entered deficit; no published dashboard at present |
| Population note | Do **not** assume a constant 206 trusts: reported counts differ by year and require source-level reconciliation |

The warehouse may contain more organisational identifiers than a year-specific analytical view because of trust changes, merging, source omissions or filtering. An apparent count mismatch must be investigated before making national comparisons.

---

# PART II — RESEARCH METHODOLOGY

## Methodology: Six-Stage Data Analytics Lifecycle

### Methodology roadmap

The methodology is organised as six consecutive stages. Select a stage to go directly to its technical explanation:

1. [Data Sourcing](#stage-1--data-sourcing) — obtain authoritative NHS England TAC data and define source controls.
2. [Data Ingestion](#stage-2--data-ingestion) — capture source workbooks and load raw records to Bronze.
3. [Data Cleaning & Transformation](#stage-3--data-cleaning--transformation) — standardise, validate and conform records in Silver.
4. [Data Modelling & Analytics](#stage-4--data-modelling--analytics) — organise dimensions, facts and financial KPIs in Silver and Gold.
5. [Data Preparation for Reporting](#stage-5--data-preparation-for-reporting) — prepare curated datasets and exports.
6. [Data Visualisation & Insights](#stage-6--data-visualisation--insights) — design and communicate Power BI financial analysis.

The project is explained using stages named for **the work performed**, not merely the software or storage location.

![NHS financial analytics data engineering architecture with Bronze Silver Gold layers](docs/images/data_engineering_architecture.svg)

| Stage | Purpose | Main assets / implementation |
| --- | --- | --- |
| **1. Data Sourcing** | Identify authoritative data, accounting definitions and versions | NHS England TAC publications; source registers |
| **2. Data Ingestion** | Preserve source snapshots and land source records | `data/raw/`, Python ingestion, MySQL Bronze |
| **3. Data Cleaning & Transformation** | Standardise, validate and conform accounting data | Python transformation/validation, MySQL Silver |
| **4. Data Modelling & Analytics** | Build analytical relationships, reporting views and KPIs | Silver star schema, Gold views, analytical SQL |
| **5. Data Preparation for Reporting** | Supply curated tables in usable reporting form | CSV exports from Gold/Silver for Power BI |
| **6. Data Visualisation & Insights** | Communicate financial results and explore variations | Power BI model design, DAX definitions; report pending |

**Technical architecture:** `nhs_bronze` is the raw landing area, `nhs_silver` contains conformed provider and TAC records, and `nhs_gold` exposes analytical reporting views. The stages overlap these storage layers: landing into Bronze is ingestion; transformation into Silver follows; Gold views are built for analysis and then exported for reporting.

The [simplified lifecycle diagram](docs/images/pipeline_architecture_stages.svg) and [original technical architecture diagram](docs/images/pipeline_architecture.png) are retained as supporting references. The diagram above separates the main data flow from cross-cutting quality and reconciliation controls.

---

## Stage 1 — Data Sourcing

**Purpose.** Establish the source, time frame and accounting basis for the investigation.

I selected NHS England's annual Trust Accounts Consolidation (TAC) releases to investigate the financial position of NHS Trusts and Foundation Trusts from 2021/22 to 2023/24. The source documents represent public financial reporting information, rather than a manually compiled sample. Each year requires separate NHS Trust and Foundation Trust workbooks, giving six expected input workbooks.

The main decisions at this stage are which reporting years to examine, which accounting schedules to use, and how to record the official publication, version, provider population and monetary units. Documenting these choices allows a later reviewer to distinguish genuine financial changes from differences in source coverage or reporting definitions.

**Output:** Six identified source workbooks and a documented source/accounting scope.

**Technical notebook:** [Stage 1 — Data Sourcing](notebook/01-data-sourcing/README.md), including source detail, publication conventions and file provenance.

---

## Stage 2 — Data Ingestion

**Purpose.** Bring the published data into a controlled environment while preserving its origin.

I designed the ingestion process to retain the original Excel files as the fixed source snapshot and use Python to load the relevant financial records and provider lists into the MySQL Bronze layer. Keeping the raw inputs separate from transformed records provides a reference point when discrepancies appear later in the analysis.

The process also captures the financial year, trust type and source-file context. This is essential because the project combines several annual releases that may not have identical column naming or organisational coverage. Repeatable ingestion is an objective, but full idempotence across all warehouse layers still requires testing.

**Output:** Traceable source records in the Bronze staging area.

**Technical notebook:** [Stage 2 — Data Ingestion](notebook/02-data-ingestion/README.md), including workbook structure, raw tables and Python loading procedure.

---

## Stage 3 — Data Cleaning & Transformation

**Purpose.** Make financial records consistent and trustworthy enough to combine across reporting years.

I standardise reporting fields, normalise organisation identifiers and distinguish current-year amounts from comparative figures. I then apply checks for missing information, duplicate financial codes, sign conventions and differences in the provider population. This step is particularly important for NHS financial analysis because a missing provider or misclassified accounting line can alter a national total or the proportion of trusts reporting deficits.

Validated information is organised in the Silver layer, where providers and accounting transactions can be analysed across years. Outstanding issues must remain visible in validation results rather than be silently corrected.

**Output:** Standardised, conformed financial records and a traceable validation trail.

**Technical notebook:** [Stage 3 — Data Cleaning & Transformation](notebook/03-data-cleaning-and-transformation/README.md), including cleaning routines, Silver promotion and validation checks.

---

## Stage 4 — Data Modelling & Analytics

**Purpose.** Transform accounting records into meaningful financial indicators and comparisons.

The model separates provider information from detailed TAC financial records. SQL views then organise the long-form accounting lines into income, expenditure, workforce, profit-and-loss and balance-sheet measures. This supports year-on-year comparisons, provider benchmarking and analysis of financial pressure without losing the link to the original accounting SubCodes.

I treat **operating surplus**, **net surplus** and NHS England's published **surplus/deficit before impairments and transfers** as distinct measures. That distinction became especially important when the initial portfolio figures did not align with the official published financial balances. EBITDA and other RAG labels are analytical aids, not automatic NHS regulatory ratings.

**Output:** Analytical views and financial KPIs with explicit definitions and outstanding reconciliation checks.

**Technical notebook:** [Stage 4 — Data Modelling & Analytics](notebook/04-data-modelling-and-analytics/README.md), including the star schema, SQL view definitions, KPI logic and diagnostic queries.

---

## Stage 5 — Data Preparation for Reporting

**Purpose.** Prepare consistent datasets for a business intelligence report.

I separate reporting preparation from analytical calculation so that Power BI consumes clearly defined financial tables rather than reproducing complex and potentially inconsistent SQL logic. The Gold analytical outputs are prepared as curated CSV exports, including provider information, annual financial summaries, expenditure categories and workforce measures.

Before loading these files into the reporting model, the exported totals, provider-year grain, relationship keys and units must be checked against the database. This is necessary to avoid inflating amounts when different fact tables are joined or accidentally aggregating percentage measures.

**Output:** Reporting-ready datasets, subject to a verified fresh export and reconciliation.

**Technical notebook:** [Stage 5 — Data Preparation for Reporting](notebook/05-data-preparation-for-reporting/README.md), including export files, grain and Power BI data-model preparation.

---

## Stage 6 — Data Visualisation & Insights

**Purpose.** Turn validated financial analysis into information that finance professionals and board members can understand and explore.

The proposed Power BI report is designed to explain changes in provider financial position, income and expenditure, cost pressures, workforce costs and differences across trusts. A useful executive view should show clearly defined financial measures, reporting years and populations, with enough detail for a reader to investigate an unusual figure.

The dashboard is **not yet published**. Its final results should be produced only after resolving the financial reconciliation and validating the reporting data. The reporting design should distinguish official NHS England balances from the project's supplementary operating measures and avoid unsupported conclusions about the causes of financial pressure.

**Output:** Power BI modelling and report specifications; interactive publication remains pending.

**Technical notebook:** [Stage 6 — Data Visualisation & Insights](notebook/06-data-visualisation-and-insights/README.md), including Power BI model guidance, proposed report pages and DAX references.

---

# PART III — FINDINGS, VALIDATION AND PROJECT OUTCOMES

## Financial Findings and Reconciliation

### Published national benchmarks

The authoritative external benchmarks for this period, based on the NHS England definition **before impairments and transfers**, are:

| Reporting year | Published balance | Official deficit providers | Deficit share |
| --- | ---: | ---: | ---: |
| 2021/22 | +£562m | 74 of 215 | 34.4% |
| 2022/23 | −£457m | 105 of 212 | 49.5% |
| 2023/24 | −£2,312m | 136 of 211 | 64.5% |

*These are official NHS England observations, not independently reproduced project results.* The trend indicates deterioration in the reported balance, but the accounting-policy changes and below-operating items require care in attributing its causes.

### Why the old project headline does not reconcile

Previous versions of the project reported operating results of approximately **+£1.6bn**, **+£148m** and **−£1.6bn** over the same period and counted 37, 85 and 124 trusts in operating deficit. Those figures were not independently reproduced during this documentation review. They reflect a **different measure and potentially a different population** from the published series. A subtraction of one from the other is a diagnostic gap, not an explained accounting reconciliation.

The [financial reconciliation workpaper](reports/nhs_financial_reconciliation.md) records the preliminary comparison, a verified published 2022/23 accounting bridge, relevant code issues, diagnostic SQL, and tasks required to complete the work.

### Requirements for completing the reconciliation

- Re-obtain the exact six official workbooks and validate their contents and provider rosters.
- Generate per-trust/year output for `SCI0140A`, `SCI0240` and relevant below-operating items.
- Trace the official before-impairments-and-transfers measure through published accounts and reporting definitions.
- Reconstruct appropriate inter-provider and charity-related consolidation adjustments from the official accounts where necessary.
- Align the definition and population used for counting trusts in deficit.
- Explain the 2023/24 IFRS 16/PFI comparability effect.
- Produce a signed-off variance bridge by financial year with material differences explained.
- Regenerate reporting exports and Power BI results from validated rather than merely plausible totals.

No number should be changed solely to match an external benchmark. Unresolved differences should remain visible until their accounting or data cause is known.

---

## Data Quality, Auditability and Limitations

### Controls that make the project credible

**Source traceability:** The chain should retain source filename → provider/ODS code → year → worksheet → SubCode → raw amount → transformation → analytical KPI. Store an import identifier, checksum and exceptions alongside the actual results where available.

**Completeness:** Check that both trust types and each annual file are represented. A dimension containing 215 provider IDs does not mean all 215 are active and present in every annual analysis.

**Uniqueness:** Check source keys and annual trust rows separately; careless pivoting with `MAX(CASE ...)` can conceal duplicate source records rather than resolve them.

**Accounting validity:** Validate the sign of expenses, the unit of amounts, below-operating charges, impairments/transfers and consolidation adjustments. Similar-sounding surplus measures are not necessarily comparable.

**Statistical interpretation:** A higher spending percentage or a negative margin can identify areas for investigation but is not proof of inefficiency, poor management or reduced service quality.

### Implementation and security issues requiring follow-up

| Observation | Impact | Status |
| --- | --- | --- |
| The official-balance measure is not yet reconciled to project-generated outputs | Published and model-derived figures must not be combined as if equivalent | Open |
| Operating-based `is_deficit` differs from official before-impairments-and-transfers classification | Incorrect comparison of deficit counts | Open |
| Provider population may be filtered by positive income or altered by source coverage | Year-on-year denominators may not match NHS England | Open |
| `MAX(CASE...)` pivots need duplicate-key verification | May mask source duplication or incorrect record selection | Open |
| Validation and reporting/export Python scripts still include hard-coded MySQL credentials | Security exposure; inconsistent environment setup | Open |
| Local source files and populated database were unavailable for a fresh independent run in this review | Results cannot be marked fully reproduced | Open |
| Dashboard is not published | No user-facing interactive report to validate | Open |

**Credential guidance:** `load_tac_data.py` now expects an environment-supplied `DB_PASSWORD`, but `python/transformation/validate_tac_data.py` and `python/reporting/export_for_powerbi.py` still need the same refactor. Never commit real passwords; rotate a password that has already been exposed in Git history. Changes to application code and history must be handled separately and reviewed.

### Meaning of validation in this project

A *passed automated check* means its specified rule passed during that run. It does **not** independently establish that every accounting field is correct or that published NHS balances have been reproduced. Final sign-off requires row-level/source-level evidence and a transparent reconciliation bridge.

---

## Reproducibility and Operational Workflow

### Prerequisites

- Supported Python installation and dependencies from the repository environment/requirements files.
- A locally available MySQL server with sufficient disk capacity for the TAC extracts.
- Source TAC workbooks obtained from NHS England for the specified financial years.
- Appropriate environment-based database credentials.
- Power BI Desktop for the downstream reporting model, if using the planned dashboard workflow.

### Intended sequence

```text
1. Obtain and register source workbooks (Stage 1).
2. Load source sheets into MySQL Bronze (Stage 2).
3. Transform, map and validate Bronze -> Silver (Stage 3).
4. Create Gold views and validate KPI/grain definitions (Stage 4).
5. Export reviewed model tables into reporting CSVs (Stage 5).
6. Import and validate in Power BI; develop final reports (Stage 6).
7. Reconcile all published-account comparators before releasing final financial findings.
```

Illustrative entry points:

```bash
# Execute from the repository root after configuring a secure local database.
# Check the SQL schema creation and migration instructions before loading.
python python/ingestion/load_tac_data.py
python python/transformation/validate_tac_data.py
python python/reporting/export_for_powerbi.py
```

This is **not a complete one-command reproducibility guarantee**: the SQL schema, views, source files, local environment and unresolved credential inconsistencies must be addressed first. Do not run the last two scripts with historical hard-coded passwords; refactor them to environment variables and rotate exposed credentials.

The SQL views under `sql/views/` and schema scripts under `sql/schema/` must be applied in dependency order. The extensive `create_tables_mysql.sql` includes database objects and must be reviewed for destructive `DROP` operations before running against any valued database. The project should eventually offer a versioned setup script and automated integration test that confirm schema, ingestion, uniqueness, financial mapping, export consistency and replay behaviour.

### Outputs to retain for an auditable run

A reproducible run should archive checksums of six TAC inputs, schema/script revision, Python environment metadata, row counts, provider/year coverage, validation report, exported reporting tables and a signed-off financial reconciliation summary.

---

## Project Deliverables and Next Steps

| Deliverable | Repository evidence | Status |
| --- | --- | --- |
| Source discovery and file conventions | Stage 1–2 notes, ingestion script | Documented; source snapshot not bundled |
| Python data ingestion and transformation | `python/ingestion/`, `python/transformation/` | Code exists; fresh run not verified |
| Bronze/Silver/Gold MySQL architecture | `sql/schema/`, `sql/views/` | Code exists; end-to-end database validation pending |
| Financial analytical SQL and KPIs | `sql/analysis/`, `v_kpis.sql` | Implemented definitions; accounting sign-off pending |
| Financial reconciliation workpaper | [Reconciliation report](reports/nhs_financial_reconciliation.md) | Preliminary; final numerical bridge pending |
| Curated export process | [Power BI export script](python/reporting/export_for_powerbi.py) | Implemented; current export run not verified |
| Power BI modelling and DAX design | `power_bi/` | Design assets provided; published dashboard pending |
| Full reproducible validated case study | Source-to-report run, reconciled results, verified dashboard | Outstanding |

### Recommended order of completion

1. Remove remaining embedded credentials and standardise database configuration.
2. Reconcile source provider populations, TAC accounting codes and national financial balances.
3. Execute automated validation and fresh end-to-end pipeline runs, including duplicate/reload tests.
4. Recalculate financial analysis and amend the detailed [2023/24 review](reports/nhs_sector_financial_review_2324.md) where required.
5. Produce and test a genuine Power BI report with reconciled values, then add screenshots and publication details.
6. Update the concise [README](README.md) with the final independently validated findings.

### What the project demonstrates

Even in its current state, the repository demonstrates a coherent approach to handling public-sector financial datasets: source identification, repeatable ingestion, dimensional modelling, accounting-coded SQL, data validation, KPI specification and reporting design. The unfinished reconciliation and reporting work is explicitly disclosed rather than presented as completed impact.

---

## Glossary and Reference Material

| Term | Meaning |
| --- | --- |
| NHS Trust / Foundation Trust | NHS provider organisations, with different legal/accountability arrangements |
| TAC | Trust Accounts Consolidation, NHS England's annual provider financial reporting dataset |
| SoCI | Statement of Comprehensive Income |
| ODS code | Organisational identifier used to distinguish providers |
| SubCode | TAC accounting line identifier used to interpret an amount |
| CY / PY | Current-year / prior-year comparative fields |
| WTE | Whole-Time Equivalent workforce measure |
| PDC dividend | Public Dividend Capital-related finance charge |
| EBITDA | Earnings before interest, tax, depreciation and amortisation |
| RAG | Red/Amber/Green analytical classification; not automatically an NHS regulatory rating |
| Bronze / Silver / Gold | Raw landing / conformed data / curated analytical presentation layers |
| Reconciliation | Explaining the bridge between defined accounting measures and published statements |

### Primary references

- [NHS England TAC publications](https://www.england.nhs.uk/financial-accounting-reporting-systems/nhs-england-finance-returns-publications-guidance/trust-accounts-consolidation-tac/)
- [NHS provider consolidated accounts 2021/22](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2021-to-2022)
- [NHS provider consolidated accounts 2022/23](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2022-to-2023)
- [NHS provider consolidated accounts 2023/24](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2023-to-2024)
- [NHS England Oversight Framework](https://www.england.nhs.uk/nhs-oversight-framework/)

### Repository technical references

- [Financial reconciliation and accounting bridge](reports/nhs_financial_reconciliation.md)
- [Financial review and earlier analytical findings](reports/nhs_sector_financial_review_2324.md) — **requires reconciliation review**
- [TAC SubCode data dictionary](agent_docs/data_dictionary.md)
- [KPI definitions and project thresholds](agent_docs/kpi_definitions.md)
- [SQL views](sql/views/) and [analysis SQL](sql/analysis/)
- [Python ingestion, transformation and export](python/)
- [Power BI model guide](power_bi/setup_guide.md) and [DAX](power_bi/dax_measures.md)
- [Original full project documentation archive](docs/project-documentation-history-20261028.md)

---

*This document is a transparent technical and financial research record. The published-account comparison and individual provider findings should be described as fully validated only after completing the pending source-data reconciliation and reproducibility checks.*
