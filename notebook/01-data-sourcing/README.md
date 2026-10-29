# Stage 1: Data Sourcing

**Implementation:** NHS England TAC publications and source provenance.

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
  DAX measures on import into Power BI (see [stage ⑥](../06-data-visualisation-and-insights/README.md)).
  £000 does not imply whole numbers: the verified sources contain values to five decimal places.

## Verified source manifest — 29 October 2026

These are the exact production workbook bytes used by the completed source-to-report run. The workbooks
are git-ignored, so a future reproduction should calculate SHA-256 before loading and compare it with this
manifest rather than relying on filenames alone.

| Workbook | Approx. size | SHA-256 |
|---|---:|---|
| `TAC_NHS_foundation_trusts_2021-22.xlsx` | 33 MB | `e70b6db73f8662fe821d4a0e84c09e5d50e5f3cfd024a906de54351a0ac5aaed` |
| `TAC_NHS_foundation_trusts_2022-23.xlsx` | 36 MB | `082722c3120dad6a80a6c7402306553213c4ea554b586b62f8b0fd6769f5037c` |
| `TAC_NHS_foundation_trusts_2023-24.xlsx` | 38 MB | `358657e90e3e216d3d3cc4cf634a351ce24228460ac6cf8aa19ab6731e8b159c` |
| `TAC_NHS_trusts_2021-22.xlsx` | 16 MB | `6b803ea88c3dc9c7b4185173b48c230891f590d9fafb11fa238544e211a1186d` |
| `TAC_NHS_trusts_2022-23.xlsx` | 20 MB | `1d5c8e30e64e598a0ca83a55c803aab19583ff812e803e663dd9407cdce751fd` |
| `TAC_NHS_trusts_2023-24.xlsx` | 18 MB | `80330fd3dadaacea8746f7de6335175e0e81437404b17ccd66af9ac21d883e91` |

The ingestion audit stores the same SHA-256 alongside file size, financial year, trust type, row counts,
integrity results and final load status in `nhs_bronze.import_batch`.

## No Code Here — By Design

There's nothing to link to in this stage's "Relevant Files" the way later stages link to a `.py` or `.sql`
file, because nothing in this repository runs here. That absence is itself the point: it's the boundary
between "data NHS England is responsible for" and "code I'm responsible for," which is exactly why
[stage ②](../02-data-ingestion/README.md) treats the downloaded files as fixed input to audit against, not
something to clean in place.

---

## Relevant Files

| File | What to Read |
|------|-------------|
| [PROJECT_DOCUMENTATION.md](../../PROJECT_DOCUMENTATION.md), stage ① | The narrative version of this stage, plus the business case for the whole project |
| [PROJECT_DOCUMENTATION.md](../../PROJECT_DOCUMENTATION.md), Sections 1–3 | NHS background, the financial crisis in numbers, project objectives |

---

*Next: [Stage ② — Raw Excel Files](../02-data-ingestion/README.md)*
