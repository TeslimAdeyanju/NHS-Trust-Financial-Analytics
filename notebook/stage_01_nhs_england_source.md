# Stage ① — NHS England (Source)

> There is no code in this stage. It exists so every later stage has a named starting point:
> the exact publication this entire project is built on, and why it can't be queried directly.

---

## What TAC Actually Is

**Trust Accounts Consolidation (TAC)** is NHS England's annual process of collecting the audited
statutory accounts of every NHS Trust and NHS Foundation Trust, in a standardised Excel template, and
publishing the consolidated result as open data.

- **Source:** [NHS England — Trust Accounts Consolidation (TAC)](https://www.england.nhs.uk/financial-accounting-reporting-systems/nhs-england-finance-returns-publications-guidance/trust-accounts-consolidation-tac/)
- **Cadence:** annual, published after year-end audit sign-off — this is why the dataset has no monthly
  grain anywhere downstream. TAC is a year-end return, not an in-year management report.
- **Format:** one workbook per year per trust population (NHS Trusts / Foundation Trusts are published
  separately, so a given financial year is two files, not one)
- **Access:** no API. Files are downloaded manually from the page above after accepting NHS England's
  terms of use — this project's ingestion pipeline starts from files already on disk in `data/raw/`,
  because there is nothing upstream of that to call.

## Why This Stage Exists on Its Own

Every other stage in this pipeline is something *I* built. This one isn't — it's the fixed, external
authority everything else is validated against. Keeping it as its own stage (rather than folding it into
"raw files") makes an important distinction explicit: `data/raw/*.xlsx` is a **copy**, not the source. If a
number ever looks wrong, the question "is this what NHS England actually published, or did my pipeline
introduce the error?" always has an answer, because the original publication is a fixed, external
reference point independent of anything in this repository.

## The Money and Year Conventions, Set Once Here

Two conventions established at the source apply to every table, column, and file downstream, without
exception:

- **Financial year:** 1 April – 31 March, labelled `YYYY/YY` (e.g. `2023/24`). Every filter in every SQL
  view, every Python script, and every DAX measure in this project uses `financial_year` — never a
  calendar-year or calendar-month column, because none exists.
- **Currency:** every monetary figure NHS England publishes is in **£ thousands (£000s)**. This project
  keeps that unit all the way through SQL and CSV, and converts to £m only at the very last step — inside
  DAX measures on import into Power BI (see [stage ⑥](stage_06_powerbi_dashboard.md)).

## No Code Here — By Design

There's nothing to link to in this stage's "Relevant Files" the way later stages link to a `.py` or `.sql`
file, because nothing in this repository runs here. That absence is itself the point: it's the boundary
between "data NHS England is responsible for" and "code I'm responsible for," which is exactly why
[stage ②](stage_02_raw_excel_files.md) treats the downloaded files as fixed input to audit against, not
something to clean in place.

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md), stage ① | The narrative version of this stage, plus the business case for the whole project |
| [PROJECT_DOCUMENTATION.md](../PROJECT_DOCUMENTATION.md), Sections 1–3 | NHS background, the financial crisis in numbers, project objectives |

---

*Next: [Stage ② — Raw Excel Files](stage_02_raw_excel_files.md)*
