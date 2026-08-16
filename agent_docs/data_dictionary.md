# Data Dictionary

## Source Files (downloaded to data/raw/)

| File | Size | Trusts | Years covered |
|------|------|--------|---------------|
| `TAC_NHS_trusts_2021-22.xlsx` | 16MB | 66 NHS Trusts | 2021/22 (CY) + 2020/21 (PY) |
| `TAC_NHS_foundation_trusts_2021-22.xlsx` | 33MB | 140 Foundation Trusts | 2021/22 (CY) + 2020/21 (PY) |
| `TAC_NHS_trusts_2022-23.xlsx` | 20MB | 66 NHS Trusts | 2022/23 (CY) + 2021/22 (PY) |
| `TAC_NHS_foundation_trusts_2022-23.xlsx` | 36MB | 140 Foundation Trusts | 2022/23 (CY) + 2021/22 (PY) |
| `TAC_NHS_trusts_2023-24.xlsx` | 18MB | 66 NHS Trusts | 2023/24 (CY) + 2022/23 (PY) |
| `TAC_NHS_foundation_trusts_2023-24.xlsx` | 38MB | 140 Foundation Trusts | 2023/24 (CY) + 2022/23 (PY) |
| `TAC_illustrative_2023-24.xlsx` | 299KB | Reference only | Schema/subcode guide |

Total providers: **206** (66 NHS Trusts + 140 Foundation Trusts)
Total data rows per file: ~481,000 (trusts) / ~1.1M (foundation trusts)

---

## Raw Data Structure

Every data file contains a sheet called **"All data"** with exactly **7 columns**:

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `OrganisationName` | string | Full legal name of the Trust | `Barts Health NHS Trust` |
| `WorkSheetName` | string | TAC schedule name | `TAC02 SoCI` |
| `TableID` | integer | Table number within the sheet | `1` |
| `MainCode` | string | Column identifier (sheet + CY/PY + table) | `A02CY01` |
| `RowNumber` | integer | Row position in original form | `12` |
| `SubCode` | string | Unique line item identifier | `SCI0100A` |
| `Total` | integer | Value in **£000s** | `350689` |

### MainCode convention

Format: `A{sheet_number}{CY|PY}{table_number}`

| Part | Meaning | Example |
|------|---------|---------|
| `A02` | TAC sheet number (02 = SoCI) | A02, A06, A08, A09 |
| `CY` | Current Year data | 2023/24 in the 2023/24 file |
| `PY` | Prior Year data | 2022/23 in the 2023/24 file |
| `01` | Table ID within sheet | 01, 02, 03… |

**Important:** Each annual file contains BOTH current year (CY) and prior year (PY) rows.
When building a multi-year series, use CY rows only to avoid double-counting.

### "List of Providers" sheet

| Column | Description | Example |
|--------|-------------|---------|
| `Full name of Provider` | Trust name (matches OrganisationName) | `Barts Health NHS Trust` |
| `NHS code` | 3-character ODS code | `R1H` |
| `Region` | NHS England region | `London` |
| `Sector` | Trust type | `Acute`, `Mental Health`, `Community`, `Ambulance` |
| `Comments` | Exclusion notes if applicable | null or exclusion reason |

---

## TAC Worksheet Schedule Reference

| WorkSheetName | Content | Key SubCode prefix |
|---------------|---------|-------------------|
| `TAC02 SoCI` | Statement of Comprehensive Income (summary P&L) | SCI, SOC |
| `TAC03 SoFP` | Statement of Financial Position (balance sheet) | SFP |
| `TAC04 SOCIE` | Statement of Changes in Equity | SCE |
| `TAC05 SoCF` | Statement of Cash Flows | SCF |
| `TAC06 Op Inc 1` | Operating income from patient care (by nature + source) | INC0xxx |
| `TAC07 Op Inc 2` | Other operating income | INC1xxx |
| `TAC08 Op Exp` | Operating expenditure (detailed breakdown) | EXP |
| `TAC09 Staff` | Staff costs (pay) and WTE numbers | STA |
| `TAC11 Finance & other` | Finance income, finance expense, PDC | FIN |
| `TAC12 Impairment` | Asset impairments | IMP |
| `TAC13 Intangibles` | Intangible assets | INT |
| `TAC14 PPE` | Property, Plant and Equipment | PPE |
| `TAC14A RoU Assets` | Right-of-use assets (IFRS 16 leases) | ROU |
| `TAC18 Receivables` | Debtors and receivables | REC |
| `TAC19 CCE` | Cash and cash equivalents | CCE |
| `TAC20 Payables` | Creditors and payables | PAY |
| `TAC22 Provisions` | Provisions for liabilities | PRV |
| `TAC28 Disclosures` | Statutory disclosures (NHS trusts only) | DIS |
| `TAC29 Losses+SP` | Losses and special payments | LSP |

---

## Key SubCodes for Analytics

### TAC02 SoCI — Summary Income & Expenditure

| SubCode | Description | Sign |
|---------|-------------|------|
| `SCI0100A` | Operating income from patient care activities | + |
| `SCI0110A` | Other operating income | + |
| `SCI0125A` | Operating expenses (total, shown negative) | − |
| `SCI0140A` | **Operating surplus / (deficit)** | +/− |
| `SCI0150` | Finance income | + |
| `SCI0160` | Finance expense | − |
| `SCI0170` | PDC dividend expense | − |
| `SCI0180` | Net finance costs | +/− |
| `SCI0190A` | Other gains / (losses) | +/− |
| `SCI0240` | **Surplus / (deficit) for the year** | +/− |
| `SOC0190` | **Total comprehensive income / (expense)** | +/− |

### TAC06 Op Inc 1 — Patient Care Income (by nature)

| SubCode | Description |
|---------|-------------|
| `INC0197` | API income — Variable (acute, activity-based) |
| `INC0198` | API income — Fixed (acute, non-activity) |
| `INC0200` | High cost drugs income from commissioners |
| `INC0210` | Other NHS clinical income (acute) |
| `INC0231` | API income (mental health) |
| `INC0302` | API income (community) |
| `INC0330` | Private patient income |
| `INC0332` | Pay award central funding |
| `INC0340` | Other clinical income |
| `INC0350` | **Total income from patient care activities** |

### TAC06 Op Inc 1 — Patient Care Income (by source, Table 2)

| SubCode | Description |
|---------|-------------|
| `INC1100` | NHS England |
| `INC1115` | Integrated Care Boards |
| `INC1140` | Local authorities |
| `INC1170` | Non-NHS: private patients |
| `INC1180` | Non-NHS: overseas patients |
| `INC1220` | **Total income from patient care (by source)** |

### TAC07 Op Inc 2 — Other Operating Income

| SubCode | Description |
|---------|-------------|
| `INC1230A` | Research and development (IFRS 15) |
| `INC1240A` | Education and training |
| `INC1280A` | Non-patient care services to other bodies |
| `INC1320` | Income in respect of employee benefits |
| `INC1360` | **Total other operating income** |
| `INC1365` | **Total operating income** |

### TAC08 Op Exp — Operating Expenditure

| SubCode | Description | Category |
|---------|-------------|----------|
| `EXP0100` | Purchase of healthcare from NHS bodies | Non-pay |
| `EXP0110` | Purchase of healthcare from non-NHS bodies | Non-pay |
| `EXP0130` | **Staff and executive directors costs** | Pay |
| `EXP0140` | Non-executive directors | Pay |
| `EXP0150` | Supplies and services — clinical | Non-pay |
| `EXP0160` | Supplies and services — general | Non-pay |
| `EXP0170` | Drugs costs | Non-pay |
| `EXP0190` | Consultancy | Non-pay |
| `EXP0200` | Establishment | Non-pay |
| `EXP0210` | Premises — business rates | Non-pay |
| `EXP0220` | Premises — other | Non-pay |
| `EXP0240` | **Depreciation** | Non-pay (excl. from EBITDA) |
| `EXP0250` | **Amortisation** | Non-pay (excl. from EBITDA) |
| `EXP0260` | Impairments net of reversals | Non-pay (excl. from EBITDA) |
| `EXP0290A` | Clinical negligence premium (NHS Resolution) | Non-pay |
| `EXP0300` | Research and development — staff costs | Pay |
| `EXP0320` | Education and training — staff costs | Pay |
| `EXP0350` | Redundancy costs — staff | Pay |
| `EXP0370` | PFI / LIFT on-SoFP charges | Non-pay |
| `EXP0390` | **Total operating expenditure** | |

### TAC09 Staff — Pay Costs and WTE Numbers

**Table: Note 5.2 Employee Expenses (MainCode A09CY01 = Total, A09CY01P = Permanent, A09CY01O = Other)**

| SubCode | Description | Unit |
|---------|-------------|------|
| `STA0100` | Salaries and wages | £000 |
| `STA0110` | Social security costs | £000 |
| `STA0120` | Apprenticeship levy | £000 |
| `STA0130` | Pension cost — employer contributions | £000 |
| `STA0150` | Pension cost — other | £000 |
| `STA0190` | Temporary staff — external bank | £000 |
| `STA0200` | Temporary staff — agency/contract | £000 |
| `STA0220` | **Total gross staff costs** | £000 |
| `STA0250` | **Total staff costs** | £000 |

**Table: Note 5.3 Average WTE numbers (MainCode A09CY01)**

| SubCode | Description | Unit |
|---------|-------------|------|
| `STA0310` | Medical and dental (WTE) | No. |
| `STA0320` | Ambulance staff (WTE) | No. |
| `STA0330` | Administration and estates (WTE) | No. |
| `STA0340` | Healthcare assistants and other support (WTE) | No. |
| `STA0350` | Nursing, midwifery and health visiting (WTE) | No. |
| `STA0370` | Scientific, therapeutic and technical (WTE) | No. |
| `STA0390` | Social care staff (WTE) | No. |
| `STA0400` | Other (WTE) | No. |
| `STA0410` | **Total average WTE** | No. |

---

## Data Quality Notes

- **Excluded providers:** Some trusts are excluded per-file where board adoption or audit opinion was outstanding at publication. Check the "List of Providers" Comments column.
- **Prior Year rows:** Each file contains PY rows (MainCode contains `PY`). Use only CY rows to avoid duplication when combining files.
- **Zero values:** Zero is a valid submission — do not treat as null.
- **Negative values:** Expenditure lines are stored as positive numbers in the raw data; the SoCI uses sign convention (+income, −expenditure). Always check the `Expected sign` column in the illustrative file.
- **NHS Charitable Funds:** Data includes any locally consolidated NHS charitable funds. SubCodes prefixed `OPX`, `OPO`, `OPP` relate to charitable fund activity.
- **Foundation Trust vs NHS Trust files:** Identical column structure. TAC28 (Disclosures) tables 6–8 exist only in NHS Trust files, not Foundation Trust files.


---

## Full SubCode Reference (all 28 real TAC worksheets)

The tables above cover the ~59 SubCodes hand-curated for the views that ship in this project (TAC02, TAC06,
TAC07, TAC08, TAC09). The raw TAC files actually contain SubCodes across **28 real worksheets** — every
schedule NHS England publishes has real rows in the source Excel files, not just the ones this project
pivots into a dedicated view. The tables below cover the remaining 22 worksheets (everything except
TAC02/06/07/08/09, already documented above, and TAC14X RoU Assets PY, which reuses TAC14A's exact SubCode
values as a prior-year comparative).

Generated from `data/raw/TAC_illustrative_2023-24.xlsx` (NHS England's own schema reference file) by
`python/ingestion/build_subcode_reference.py` — re-run that script if NHS England revises the illustrative
file in a future year. These SubCodes are seeded into `dim_subcode` (see `sql/schema/create_tables_mysql.sql`)
with `analytics_category = NULL` — they exist for labelling/lookup, not for any pivot grouping like
`v_expenditure_breakdown`'s PAY/NON_PAY split.

## TAC03 SoFP

| SubCode | Description | Sign |
|---------|-------------|------|
| `BAL1100` | Intangible assets | + |
| `BAL1110` | Property, plant and equipment | + |
| `BAL1115` | Right of use assets | + |
| `BAL1120` | Investment property | + |
| `BAL1130` | Investments in joint ventures and associates | + |
| `BAL1140` | Other investments / financial assets | + |
| `BAL1150` | Receivables | + |
| `BAL1170` | Other assets | + |
| `BAL1180` | Total non-current assets | + |
| `BAL1190` | Inventories | + |
| `BAL1200` | Receivables | + |
| `BAL1210` | Other investments / financial assets | + |
| `BAL1220` | Other assets | + |
| `BAL1230` | Non-current assets held for sale and assets in disposal groups | + |
| `BAL1240` | Cash and cash equivalents | + |
| `BAL1250` | Total current assets | + |
| `BAL1260` | Trade and other payables | - |
| `BAL1270` | Borrowings | - |
| `BAL1280` | Other financial liabilities | - |
| `BAL1290` | Provisions | - |
| `BAL1300` | Other liabilities | - |
| `BAL1310` | Liabilities in disposal groups | - |
| `BAL1320` | Total current liabilities | - |
| `BAL1330` | Total assets less current liabilities | +/- |
| `BAL1340` | Trade and other payables | - |
| `BAL1350` | Borrowings | - |
| `BAL1360` | Other financial liabilities | - |
| `BAL1370` | Provisions | - |
| `BAL1380` | Other liabilities | - |
| `BAL1390` | Total non-current liabilities | - |
| `BAL1400` | Total assets employed | +/- |
| `BAL1410` | Public dividend capital | + |
| `BAL1420` | Revaluation reserve | + |
| `BAL1430` | Financial assets at FV through OCI reserve | +/- |
| `BAL1440` | Other reserves | +/- |
| `BAL1450` | Merger reserve | +/- |
| `BAL1460` | Income and expenditure reserve | +/- |
| `BAL1470` | Non-controlling Interest | + |
| `BAL1490` | Charitable fund reserves | + |
| `BAL1500` | Total taxpayers' and others' equity | +/- |

## TAC04 SOCIE

| SubCode | Description | Sign |
|---------|-------------|------|
| `SCE0010` | Taxpayers' and others' equity at 1 April 2023 - brought forward | +/- |
| `SCE0031` | Application of IFRS 16 measurement principles to PFI liability on 1 April 2024 | +/- |
| `SCE0040` | At start of period for new FTs | +/- |
| `SCE0050` | Surplus/(deficit) for the year | +/- |
| `SCE0060` | Transfers by absorption: transfers between reserves |  |
| `SCE0065` | Transfers by absorption: transfers between reserves (charitable fund) |  |
| `SCE0070` | Transfer from reval reserve to I&E reserve for impairments arising from consumption of economic benefits |  |
| `SCE0080` | Transfers between reserves |  |
| `SCE0090` | Net impairments | +/- |
| `SCE0100` | Revaluations - property, plant and equipment | + |
| `SCE0110` | Revaluations - intangible assets | + |
| `SCE0112` | Revaluations - right of use assets | + |
| `SCE0115` | Revaluations and impairments - charitable fund assets | +/- |
| `SCE0120` | Transfer to retained earnings on disposal of assets |  |
| `SCE0130` | Share of comprehensive income from associates and joint ventures | +/- |
| `SCE0140` | Fair value gains/(losses) on financial assets mandated at FV through OCI | +/- |
| `SCE0145` | Fair value gains/(losses) on equity instruments designated at FV through OCI | +/- |
| `SCE0150` | Recycling gains/(losses) on disposal of financial assets mandated at FV through OCI | +/- |
| `SCE0160` | Foreign exchange gains/(losses) recognised directly in OCI | +/- |
| `SCE0170` | Other recognised gains and losses | +/- |
| `SCE0180` | Remeasurements of defined net benefit pension scheme liability / asset | +/- |
| `SCE0200` | Public dividend capital received | + |
| `SCE0210` | Public dividend capital repaid | - |
| `SCE0220` | Public dividend capital written off |  |
| `SCE0230` | Other movements in PDC in year (unlocked on request) | +/- |
| `SCE0240` | Reserves eliminated on dissolution (unlocked on request) | +/- |
| `SCE0250` | Other reserve movements | +/- |
| `SCE0255` | Other reserve movements - charitable fund consolidation adjustment | +/- |
| `SCE0260` | Transfer to FT upon authorisation | +/- |
| `SCE0270` | Taxpayers' and others' equity at 31 March 2024 | +/- |
| `SCE0020` | Prior period adjustment | +/- |
| `SCE0030` | Taxpayers' and others' equity at 1 April 2022 - restated | +/- |
| `SCE0032` | Implementation of IFRS 16 on 1 April 2022 | +/- |
| `SCE0055` | Gain / (loss) on transfers by absorption (modified) | +/- |

## TAC05 SoCF

| SubCode | Description | Sign |
|---------|-------------|------|
| `SCF0100A` | Operating surplus/(deficit) from continuing operations | +/- |
| `SCF0100B` | Operating surplus/(deficit) of discontinued operations | +/- |
| `SCF0100` | Operating surplus/(deficit) | +/- |
| `SCF0105` | Depreciation and amortisation | + |
| `SCF0110` | Impairments and reversals | + |
| `SCF0120` | Income recognised in respect of capital donations (cash and non-cash) | - |
| `SCF0125` | Amortisation of PFI deferred income / credit | - |
| `SCF0130` | On SoFP pension liability - employer contributions paid less net charge to the SOCI | +/- |
| `SCF0135` | (Increase)/decrease in receivables | +/- |
| `SCF0140A` | (Increase)/decrease in other assets | +/- |
| `SCF0150` | (Increase)/decrease in inventories | +/- |
| `SCF0155` | Increase/(decrease) in trade and other payables | +/- |
| `SCF0160` | Increase/(decrease) in other liabilities | +/- |
| `SCF0165` | Increase/(decrease) in provisions | +/- |
| `CFS0010` | Movements in charitable fund working capital | +/- |
| `SCF0170` | Corporation tax (paid) / received | +/- |
| `SCF0175A` | Movements in operating cash flows of discontinued operations | +/- |
| `CFS0020` | NHS charitable funds: other movements in operating cash flows | +/- |
| `SCF0175B` | Other movements in operating cash flows | +/- |
| `SCF0180` | Net cash generated from / (used in) operations | +/- |
| `SCF0185` | Interest received | + |
| `SCF0190` | Purchase of financial assets / investments | - |
| `SCF0195` | Proceeds from sales / settlements of financial assets / investments | + |
| `SCF0200` | Purchase of intangible assets | - |
| `SCF0205` | Proceeds from sales of intangible assets | + |
| `SCF0210` | Purchase of property, plant and equipment and investment property | - |
| `SCF0215` | Proceeds from sales of property, plant and equipment and investment property | + |
| `SCF0216A` | Initial direct costs or up front payments in respect of new right of use assets (lessee) | - |
| `SCF0216B` | Receipt of cash lease incentives (lessee) | + |
| `SCF0216C` | Lease termination fees paid (lessee) | - |
| `SCF0220` | Receipt of cash donations to purchase capital assets | + |
| `SCF0226` | Prepayment of PFI capital contributions (cash payments) | - |
| `SCF0227` | Finance lease receipts (principal and interest) | + |
| `CFS0030` | NHS charitable funds: net cash flows from investing activities | +/- |
| `SCF0235A` | Cash flows attributable to investing activities of discontinued operations | +/- |
| `SCF0230` | Cash movement from acquisitions of business units and subsidiaries (not absorption transfers) | +/- |
| `SCF0235` | Cash movement from disposals of business units and subsidiaries (not absorption transfers) | +/- |
| `SCF0240` | Net cash generated from/(used in) investing activities | +/- |
| `SCF0245` | Public dividend capital received | + |
| `SCF0250` | Public dividend capital repaid | - |
| `CFS1000` | Movement in loans from the Department of Health and Social Care | +/- |
| `CFS1010` | Movement in other loans | +/- |
| `SCF0275` | Other capital receipts | + |
| `SCF0280` | Capital element of lease liability repayments | - |
| `SCF0285` | Capital element of PFI, LIFT and other service concession payments | - |
| `SCF0290A` | Interest on DHSC loans | - |
| `SCF0290C` | Interest on other loans | - |
| `SCF0290B` | Other interest (e.g. overdrafts) | - |
| `SCF0295` | Interest element of lease liability repayments | - |
| `SCF0300` | Interest element of PFI, LIFT and other service concession obligations | - |
| `SCF0305` | PDC dividend (paid)/refunded | +/- |
| `SCF0310A` | Cash flows attributable to financing activities of discontinued operations | +/- |
| `CFS0040` | NHS charitable funds: net cash flows from financing activities | +/- |
| `SCF0310` | Cash flows from (used in) other financing activities | +/- |
| `SCF0315` | Net cash generated from/(used in) financing activities | +/- |
| `SCF0320` | Increase/(decrease) in cash and cash equivalents | +/- |
| `SCF0325A` | Cash and cash equivalents at 1 April - brought forward | +/- |
| `SCF0325B` | Prior period adjustments | +/- |
| `SCF0325` | Cash and cash equivalents at 1 April - restated | +/- |
| `SCF0345` | Cash and cash equivalents at start of period for new FTs | +/- |
| `SCF0350` | Cash and cash equivalents transferred by absorption | +/- |
| `SCF0115` | Unrealised gains/(losses) on foreign exchange | +/- |
| `SCF0340` | Cash transferred to NHS foundation trust upon authorisation as FT | +/- |
| `SCF0355` | Cash and cash equivalents at 31 March | +/- |

## TAC11 Finance & other

| SubCode | Description | Sign |
|---------|-------------|------|
| `FIN0010` | Interest on bank accounts | + |
| `FIN0030` | Interest income on finance leases | + |
| `FIN0040` | Interest on other investments / financial assets | + |
| `FIN0050` | NHS charitable fund investment income | + |
| `FIN0060` | Other | + |
| `FIN0070` | Total finance revenue | + |
| `SCI1210` | - Capital loans | + |
| `SCI1220` | - Revenue support / working capital loans | + |
| `SCI1240` | Interest on other loans | + |
| `SCI1250` | Interest on bank overdrafts | + |
| `SCI1260` | Interest on lease obligations | + |
| `SCI1270` | Interest on the late payment of commercial debt | + |
| `SCI1280` | - Main finance costs | + |
| `SCI1290` | - Contingent finance costs | + |
| `SCI1295` | - Remeasurement of PFI / other service concession liability resulting from change in index or rate | +/- |
| `FIN0080` | Total interest expense | + |
| `SCI1320` | Unwinding of discount on provisions | +/- |
| `SCI1330` | Other finance costs | + |
| `SCI1340` | Total finance expenditure | + |
| `FIN0089` | Total liability accruing in year under this legislation as a result of late payments | + |
| `FIN0090` | Amounts actually paid and included within other interest arising from claims made under this legislation | + |
| `FIN0100` | Compensation paid to cover debt recovery costs under this legislation | + |
| `SCI1100A` | Gains on disposal of property, plant and equipment (sale) | + |
| `SCI1100B` | Gains on disposal of PPE from creation of a finance lease (lessor) | + |
| `SCI1110` | Gains on disposal of intangible assets (sale) | + |
| `SCI1115A` | Gains on disposal of right of use assets (creation of a sublease) | + |
| `SCI1115B` | Gains on disposal of right of use assets (lease termination - lessee) | + |
| `SCI1120` | Gains on disposal of investment properties (sale) | + |
| `SCI1130A` | Gain on disposal of financial assets held at amortised cost | + |
| `SCI1130B` | Gain on disposal of other financial assets / investments | + |
| `SCI1140` | Gains on disposal of assets held for sale | + |
| `SCI1150B` | Losses on disposal of property, plant and equipment (sale or other derecognition) | - |
| `SCI1150C` | Losses on disposal of PPE from creation of a finance lease (lessor) | - |
| `SCI1160` | Losses on disposal of intangible assets (sale or other derecognition) | - |
| `SCI1165A` | Losses on disposal of right of use assets (creation of a sublease) | - |
| `SCI1165B` | Losses on disposal of right of use assets (lease termination - lessee) | - |
| `SCI1170` | Losses on disposal of investment properties (sale or other derecognition) | - |
| `SCI1180A` | Losses disposal of financial assets held at amortised cost | - |
| `SCI1180B` | Losses on disposal of other financial assets / investments | - |
| `SCI1190` | Losses on disposal of assets held for sale | - |
| `SCI1191` | Losses on disposal of peppercorn leased assets (new peppercorn lease as lessor, terminated peppercorn lease as lessee) | - |
| `SCI1150A` | Loss recognised on return of donated COVID assets to DHSC (comparative only) | - |
| `FIN0110` | Gains / losses on disposal of charitable fund assets | +/- |
| `SCI1200` | Total gains/(losses) on disposal of assets | +/- |
| `SCI1201` | Gains/(losses) on foreign exchange | +/- |
| `SCI0220A` | Fair value gains/(losses) on investment properties | +/- |
| `SCI0220B` | Fair value gains/(losses) on financial assets / investments | +/- |
| `FIN0120` | Fair value gains/(losses) on charitable fund investments & investment properties | +/- |
| `SCI0220C` | Fair value gains/(losses) on financial liabilities | +/- |
| `SCI0220D` | Recycling gains/(losses) on disposal of financial assets mandated as FV through OCI | +/- |
| `FIN0130` | Recycling gains/(losses) on disposal of charitable fund financial assets mandated as FV through OCI | +/- |
| `FIN0133` | Gains/(losses) on remeasurement of finance lease receivables (lessor) | +/- |
| `FIN0134` | Gains/(losses) on termination of finance leases (lessor) | +/- |
| `FIN0135` | Loss associated with loss of controlling interest in charitable fund | - |
| `SCI1203` | Other gains/(losses) | +/- |
| `SCI1205` | Total other gains/(losses) | +/- |
| `FIN0140` | Operating income of discontinued operations | + |
| `FIN0150` | Operating expenses of discontinued operations | - |
| `FIN0160` | Gain on disposal of discontinued operations | + |
| `FIN0170` | (Loss) on disposal of discontinued operations | - |
| `FIN0180` | Corporation tax expense attributable to discontinued operations | +/- |
| `FIN0190` | Total | +/- |

## TAC12 Impairment

| SubCode | Description | Sign |
|---------|-------------|------|
| `IMP0010` | Loss or damage resulting from normal operations | +/- |
| `IMP0015` | Over specification of assets | +/- |
| `IMP0020` | Abandonment of assets in the course of construction | +/- |
| `IMP0025` | Unforeseen obsolescence | +/- |
| `IMP0030` | Loss as a result of a catastrophe | +/- |
| `IMP0035` | Other | +/- |
| `IMP0040` | Changes in market price | +/- |
| `IMP0044` | Impairments of charitable fund assets | +/- |
| `IMP0045` | Total impairments and (reversals) charged to operating surplus / deficit | +/- |
| `IMP0050` | Total net impairments charged to revaluation reserve | +/- |
| `IMP0055` | Total impairments and (reversals) | +/- |

## TAC13 Intangibles

| SubCode | Description | Sign |
|---------|-------------|------|
| `INT0010` | Valuation / gross cost at 1 April 2023 - brought forward | + |
| `INT0040` | At start of period for new FTs | + |
| `INT0050` | Transfers by absorption | +/- |
| `INT0060` | Additions - purchased / internally generated | + |
| `INT0080` | Additions - donations of physical assets (non-cash) | + |
| `INT0090` | Additions - assets purchased from cash donations/grants | + |
| `INT0095` | Transfer of donated assets (non-cash) from consolidated charitable fund to trust | + |
| `INT0100` | Impairments charged to operating expenses | - |
| `INT0110` | Impairments charged to the revaluation reserve | - |
| `INT0120` | Reversal of impairments credited to operating expenses | + |
| `INT0130` | Reversal of impairments credited to the revaluation reserve | + |
| `INT0140` | Revaluations | +/- |
| `INT0145` | Remeasurements - retranslation gains / (losses) on foreign operations | +/- |
| `INT0150` | Reclassifications | +/- |
| `INT0160` | Transfers to/from assets held for sale and assets in disposal groups | +/- |
| `INT0170` | Disposals/derecognition | - |
| `INT0180` | Transfer to FT upon authorisation | - |
| `INT0190` | Valuation/gross cost at 31 March 2024 | + |
| `INT0200` | Accumulated amortisation at 1 April 2023 - brought forward | + |
| `INT0230` | At start of period for new FTs | + |
| `INT0240` | Transfers by absorption | +/- |
| `INT0250` | Provided during the year | + |
| `INT0255` | Transfer of donated assets (non-cash) from consolidated charitable fund to trust | - |
| `INT0260` | Impairments charged to operating expenses | + |
| `INT0270` | Impairments charged to the revaluation reserve | + |
| `INT0280` | Reversal of impairments credited to operating expenses | - |
| `INT0290` | Reversal of impairments credited to the revaluation reserve | - |
| `INT0300` | Revaluations | +/- |
| `INT0305` | Remeasurements - retranslation gains / (losses) on foreign operations | +/- |
| `INT0310` | Reclassifications | +/- |
| `INT0320` | Transfers to/from assets held for sale and assets in disposal groups | +/- |
| `INT0330` | Disposals/derecognition | - |
| `INT0340` | Transfer to FT upon authorisation | - |
| `INT0350` | Accumulated amortisation at 31 March 2024 | + |
| `INT0360` | Net book value at 31 March 2024 | + |
| `INT0020` | Prior period adjustment | +/- |
| `INT0030` | Valuation / gross cost at 1 April 2022 - restated | + |
| `INT0035` | Reclassification of existing finance leased assets to right of use assets on 1 April 2022 | - |
| `INT0210` | Prior period adjustment | +/- |
| `INT0220` | Accumulated amortisation at 1 April 2022 - restated | + |
| `INT0225` | Reclassification of existing finance leased assets to right of use assets on 1 April 2022 | - |
| `INT0390` | Information technology | + |
| `INT0400` | Development expenditure | + |
| `INT0410` | Websites | + |
| `INT0430` | Software licences | + |
| `INT0440` | Licences & trademarks | + |
| `INT0450` | Patents | + |
| `INT0460` | Other (purchased) | + |
| `INT0470` | Goodwill | + |

## TAC14 PPE

| SubCode | Description | Sign |
|---------|-------------|------|
| `PPE0010` | Valuation / gross cost at 1 April 2023 - brought forward | + |
| `PPE0040` | At start of period for new FTs | + |
| `PPE0050` | Transfers by absorption | +/- |
| `PPE0060` | Additions - purchased (including capital lifecycle additions) | + |
| `PPE0070` | Additions - IFRIC 12 scheme assets (excluding lifecycle) | + |
| `PPE0080` | Additions - donations of physical assets (non-cash) | + |
| `PPE0090` | Additions - assets purchased from cash donations/grants | + |
| `PPE0095` | Transfer of donated assets (non-cash) from consolidated charitable fund to trust | + |
| `PPE0096` | Additions - assets re-recognised at the end of an intra-government finance lease (trust was lessor) | + |
| `PPE0097` | Additions - assets re-recognised at the end of an external to government finance lease (trust was lessor) | + |
| `PPE0100` | Impairments charged to operating expenses | - |
| `PPE0110` | Impairments charged to the revaluation reserve | - |
| `PPE0120` | Reversal of impairments credited to operating expenses | + |
| `PPE0130` | Reversal of impairments credited to the revaluation reserve | + |
| `PPE0140` | Revaluations | +/- |
| `PPE0145` | Remeasurements - retranslation gains / (losses) on foreign operations | +/- |
| `PPE0150` | Reclassifications | +/- |
| `PPE0160` | Transfers to/from assets held for sale and assets in disposal groups | +/- |
| `PPE0170` | Disposals/derecognition | - |
| `PPE0172` | Disposals - new finance lease (lessor) | - |
| `PPE0151` | Reclassifications from RoU assets where ownership has transferred | + |
| `PPE0180` | Transfer to FT upon authorisation | - |
| `PPE0190` | Valuation/gross cost at 31 March 2024 | + |
| `PPE0200` | Accumulated depreciation at 1 April 2023 - brought forward | + |
| `PPE0230` | At start of period for new FTs | + |
| `PPE0240` | Transfers by absorption | +/- |
| `PPE0250` | Provided during the year | + |
| `PPE0255` | Transfer of donated assets (non-cash) from consolidated charitable fund to trust | - |
| `PPE0260` | Impairments charged to operating expenses | + |
| `PPE0270` | Impairments charged to the revaluation reserve | + |
| `PPE0280` | Reversal of impairments credited to operating expenses | - |
| `PPE0290` | Reversal of impairments credited to the revaluation reserve | - |
| `PPE0300` | Revaluations | +/- |
| `PPE0305` | Remeasurements - retranslation gains / (losses) on foreign operations | +/- |
| `PPE0310` | Reclassifications | +/- |
| `PPE0320` | Transfers to/from assets held for sale and assets in disposal groups | +/- |
| `PPE0330` | Disposals/derecognition | - |
| `PPE0332` | Disposals - new finance lease (lessor) | - |
| `PPE0311` | Reclassifications from RoU assets where ownership has transferred | - |
| `PPE0340` | Transfer to FT upon authorisation | - |
| `PPE0350` | Accumulated depreciation at 31 March 2024 | + |
| `PPE0020` | Prior period adjustment | +/- |
| `PPE0030` | Valuation / gross cost at 1 April 2022 - restated | + |
| `PPE0035` | Reclassification of existing finance leased assets to right of use assets on 1 April 2022 | - |
| `PPE0175` | Derecognition - COVID equipment returned to DHSC | - |
| `PPE0210` | Prior period adjustment | +/- |
| `PPE0220` | Accumulated depreciation at 1 April 2022 - restated | + |
| `PPE0225` | Reclassification of existing finance leased assets to right of use assets on 1 April 2022 | - |
| `PPE0335` | Derecognition - COVID equipment returned to DHSC | - |
| `PPE0360` | Owned - purchased | + |
| `PPE0380` | On-SoFP PFI contracts and other service concession arrangements | + |
| `PPE0390` | Off-SoFP PFI residual interests | + |
| `PPE0410` | Owned - donated / granted | + |
| `PPE0420` | NBV total at 31 March 2024 | + |
| `PPE0490` | Land | + |
| `PPE0500` | Buildings excluding dwellings | + |
| `PPE0510` | Dwellings | + |
| `PPE0520` | Plant & machinery | + |
| `PPE0530` | Transport equipment | + |
| `PPE0540` | Information technology | + |
| `PPE0550` | Furniture & fittings | + |

## TAC14A RoU Assets

| SubCode | Description | Sign |
|---------|-------------|------|
| `ROU0010` | Valuation / gross cost at 1 April 2023 - brought forward | + |
| `ROU0040` | At start of period for new FTs | + |
| `ROU0050` | Transfers by absorption | +/- |
| `ROU0070` | Additions - lease liability | + |
| `ROU0071` | Additions - up front lease payments (before or on commencement) | + |
| `ROU0072` | Additions - initial direct costs of obtaining a lease | + |
| `ROU0073` | Additions - cash lease incentives (reduce the RoU addition value) | - |
| `ROU0080` | Additions - peppercorn leases | + |
| `ROU0081` | Re-recognition of RoU asset at end of sublease - intra-gov sublease | + |
| `ROU0082` | Re-recognition of RoU asset at end of sublease - ext to gov sublease | + |
| `ROU0096` | Remeasurements of the lease liability | +/- |
| `ROU0097` | Dilapidation provisions arising (capitalised in RoU asset) | + |
| `ROU0098` | Dilapidation provisions reversed unused | - |
| `ROU0099` | Dilapidation provisions - change in discount rate | +/- |
| `ROU0100` | Impairments charged to operating expenses | - |
| `ROU0110` | Impairments charged to the revaluation reserve | - |
| `ROU0120` | Reversal of impairments credited to operating expenses | + |
| `ROU0130` | Reversal of impairments credited to the revaluation reserve | + |
| `ROU0140` | Revaluations | +/- |
| `ROU0145` | Remeasurements - retranslation gains / (losses) on foreign operations | +/- |
| `ROU0150` | Reclassifications | +/- |
| `ROU0171` | Disposals/derecognition - lease termination | - |
| `ROU0172` | Disposals/derecognition - peppercorn lease termination | - |
| `ROU0173` | Disposals/derecognition - new sublease (leased to intra-government body) | - |
| `ROU0174` | Disposals/derecognition - new sublease (leased to external to government) | - |
| `ROU0175` | Disposals/derecognition - new peppercorn sublease (intra-government) | - |
| `ROU0176` | Disposals/derecognition - new peppercorn sublease (ext to government) | - |
| `ROU0151` | Reclassifications to PPE where ownership has transferred | - |
| `ROU0180` | Transfer to FT upon authorisation | - |
| `ROU0190` | Valuation/gross cost at 31 March 2024 | + |
| `ROU0200` | Accumulated depreciation at 1 April 2023 - brought forward | + |
| `ROU0230` | At start of period for new FTs | + |
| `ROU0240` | Transfers by absorption | +/- |
| `ROU0250` | Provided during the year - right of use asset | + |
| `ROU0251` | Provided during the year - peppercorn leased asset | + |
| `ROU0260` | Impairments charged to operating expenses | + |
| `ROU0270` | Impairments charged to the revaluation reserve | + |
| `ROU0280` | Reversal of impairments credited to operating expenses | - |
| `ROU0290` | Reversal of impairments credited to the revaluation reserve | - |
| `ROU0300` | Revaluations | +/- |
| `ROU0305` | Remeasurements - retranslation gains / (losses) on foreign operations | +/- |
| `ROU0310` | Reclassifications | +/- |
| `ROU0331` | Disposals/derecognition - lease termination | - |
| `ROU0332` | Disposals/derecognition - peppercorn lease termination | - |
| `ROU0333` | Disposals/derecognition - new sublease (leased to intra-government body) | - |
| `ROU0334` | Disposals/derecognition - new sublease (leased to external to government) | - |
| `ROU0335` | Disposals/derecognition - new peppercorn sublease (intra-government) | - |
| `ROU0336` | Disposals/derecognition - new peppercorn sublease (ext to government) | - |
| `ROU0311` | Reclassifications to PPE where ownership has transferred | - |
| `ROU0340` | Transfer to FT upon authorisation | - |
| `ROU0350` | Accumulated depreciation at 31 March 2024 | + |
| `ROU0360` | Net book value at 31 March 2024 | + |
| `ROU0361` | Leased from other NHS providers | + |
| `ROU0362` | Leased from other DHSC group bodies | + |

## TAC15 Investments & groups

| SubCode | Description | Sign |
|---------|-------------|------|
| `IGR0020` | Prior period adjustments | +/- |
| `IGR0034` | Reclassification of existing finance leased assets classified as investment property on 1 April 2022 | + |
| `IGR0035` | Recognition of right of use assets for existing operating leases on initial application of IFRS 16 on 1 April 2022 | + |
| `IGR0040` | At start of period for new FTs | + |
| `IGR0050` | Transfers by absorption | + |
| `IGR0060` | Additions | + |
| `IGR0062` | Remeasurements of the lease liability | +/- |
| `IGR0065` | Capitalised dilapidation provisions | +/- |
| `IGR0080` | Fair value gains [taken to I&E] | + |
| `IGR0090` | Fair value losses (impairment) [taken to I&E] | - |
| `IGR0100` | Reclassifications to/from PPE | +/- |
| `IGR0105` | Reclassifications to/from RoU assets | +/- |
| `IGR0110` | Transfers to/from assets held for sale and assets in disposal groups | +/- |
| `IGR0120` | Disposals | - |
| `IGR0130` | Transfer to FT upon authorisation | - |
| `IGR0140` | Carrying value at 31 March | + |
| `IGR0200` | Prior period adjustments | +/- |
| `IGR0220` | At start of period for new FTs | + |
| `IGR0230` | Transfers by absorption | + |
| `IGR0240` | Additions | + |
| `IGR0250` | Share of profit/(loss) | +/- |
| `IGR0260` | Impairments | - |
| `IGR0270` | Reversal of impairment | + |
| `IGR0280` | Transfers to/from assets held for sale and assets in disposal groups | +/- |
| `IGR0290` | Disbursements / dividends received | - |
| `IGR0300` | Disposals | - |
| `IGR0310` | Share of Other Comprehensive Income recognised by joint ventures/associates | +/- |
| `IGR0320` | Other equity movements (translation gains/losses) | +/- |
| `IGR0330` | Transfer to FT upon authorisation | - |
| `IGR0340` | Carrying value at 31 March | + |
| `IGR0360` | Prior period adjustments | +/- |
| `IGR0380` | At start of period for new FTs | + |
| `IGR0390` | Transfers by absorption | + |
| `IGR0400` | Additions | + |
| `IGR0410` | Fair value gains [taken to I&E] (for assets held at FV through I&E) | + |
| `IGR0420` | Fair value losses [taken to I&E] (for assets held at FV through I&E) | - |
| `IGR0430` | Fair value movements [taken to OCI] (for financial assets mandated as FV through OCI) | +/- |
| `IGR0435` | Fair value movements [taken to OCI] (for equity instruments designated as FV through OCI) | +/- |
| `IGR0439` | (Increase)/decrease in credit loss allowance (stages 1 and 2) |  |
| `IGR0440` | Net impairments on credit impaired financial assets (stage 3 credit losses) |  |
| `IGR0460` | Transfers to/from assets held for sale and assets in disposal groups | +/- |
| `IGR0470` | Amortisation at the effective interest rate (assets held at amortised cost only where applicable) | +/- |
| `IGR0475` | Current portion of loans receivable transferred to current financial assets | - |
| `IGR0480` | Disposals | - |
| `IGR0490` | Transfer to FT upon authorisation | - |
| `IGR0500` | Carrying value at 31 March | + |
| `IGR0505` | Loans receivable within 12 months transferred from non-current financial assets | + |
| `IGR0510` | NLF deposits (where not considered to be cash equivalents) | + |
| `IGR0515` | Other current financial assets | + |
| `IGR0520` | Total current investments / financial assets at 31 March | + |

## TAC16 AHFS

| SubCode | Description | Sign |
|---------|-------------|------|
| `AHS0010` | NBV of non-current assets for sale and assets in disposal groups at 1 April 2023 - brought forward | + |
| `AHS0040` | At start of period for new FTs | + |
| `AHS0050` | Transfers by absorption | +/- |
| `AHS0060` | Plus assets classified as available for sale in the year | + |
| `AHS0070` | Less assets sold in year | - |
| `AHS0080` | Less impairment of assets held for sale | - |
| `AHS0090` | Plus reversal of impairment of assets held for sale | + |
| `AHS0100` | Less assets no longer classified as held for sale, for reasons other than disposal by sale | - |
| `AHS0110` | Transfer to FT upon authorisation | - |
| `AHS0120` | NBV of non-current assets for sale and assets in disposal groups at 31 March 2024 | + |
| `AHS0020` | Prior period adjustment | +/- |
| `AHS0030` | NBV of non-current assets for sale and assets in disposal groups at 1 April 2022 - restated | + |
| `AHS0130` | Provisions | + |
| `AHS0140` | Trade and other payables | + |
| `AHS0150` | Other | + |
| `AHS0160` | Total | + |

## TAC17 Inventories

| SubCode | Description | Sign |
|---------|-------------|------|
| `INV0010` | Carrying value at 1 April 2023 - brought forward | + |
| `INV0040` | At start of period for new FTs | + |
| `INV0050` | Transfers by absorption | +/- |
| `INV0060` | Additions (purchased) | + |
| `INV0061` | Additions (donated) - from DHSC | + |
| `INV0062` | Additions (donated) - from NHS provider (purchased by DHSC) | + |
| `INV0063` | Additions (donated) - from NHS provider (purchased by provider) (unlocked on request) | + |
| `INV0070` | Inventories consumed (recognised in expenses) | - |
| `INV0080` | Write-down of inventories recognised as an expense | - |
| `INV0090` | Reversal of any write down of inventories | + |
| `INV0100` | Transfer (to) / from inventory work in progress |  |
| `INV0110` | Other | +/- |
| `INV0115` | Movement in charitable funds inventories | +/- |
| `INV0120` | Transfer to FT upon authorisation | - |
| `INV0130` | Carrying value at 31 March 2024 | + |
| `INV0140` | Held at lower of cost and NRV | + |
| `INV0150` | Held at fair value less costs to sell | + |
| `INV0020` | Prior period adjustment | +/- |
| `INV0030` | Carrying value at 1 April 2022 - restated | + |
| `INV0060A` | Additions (donated) | + |

## TAC18 Receivables

| SubCode | Description | Sign |
|---------|-------------|------|
| `REC0001` | Contract receivables (IFRS 15): invoiced | + |
| `REC0002` | Contract receivables (IFRS 15): not yet invoiced / non-invoiced | + |
| `REC0005` | Contract assets (IFRS 15) | + |
| `REC0020` | Capital receivables (including accrued capital related income) | + |
| `REC0039` | Allowance for impaired contract receivables / assets | - |
| `REC0040` | Allowance for impaired other receivables | - |
| `REC0050` | Deposits and advances | + |
| `REC0060` | Prepayments (revenue) [non-PFI] | + |
| `REC0070` | Prepayments (capital) [non-PFI] | + |
| `REC0080` | PFI prepayments - capital contributions | + |
| `REC0090` | PFI lifecycle prepayments (revenue) | + |
| `REC0100` | PFI lifecycle prepayments (capital) | + |
| `REC0110` | Interest receivable (excludes finance lease interest) | + |
| `REC0119` | Finance lease receivables - invoiced / due but not yet paid | + |
| `REC0120` | Finance lease receivables - not yet invoiced / not relating to current year | + |
| `REC0125` | Operating lease receivables | + |
| `REC0130` | PDC dividend receivable | + |
| `REC0140` | VAT receivable | + |
| `REC0150` | Corporation and other taxes receivable | + |
| `REC0155` | Clinician pension tax provision reimbursement funding from NHSE | + |
| `REC0160` | Other receivables | + |
| `REC0165` | NHS charitable funds: receivables | + |
| `REC0170` | Total current receivables | + |
| `REC0171` | Contract receivables (IFRS 15): invoiced | + |
| `REC0172` | Contract receivables (IFRS 15): not yet invoiced / non-invoiced | + |
| `REC0175` | Contract assets (IFRS 15) | + |
| `REC0190` | Capital receivables (including accrued capital related income) | + |
| `REC0209` | Allowance for impaired contract receivables / assets | - |
| `REC0210` | Allowance for impaired other receivables | - |
| `REC0220` | Deposits and advances | + |
| `REC0230` | Prepayments (revenue) [non-PFI] | + |
| `REC0240` | Prepayments (capital) [non-PFI] | + |
| `REC0250` | PFI prepayments - capital contributions | + |
| `REC0260` | PFI lifecycle prepayments (revenue) | + |
| `REC0270` | PFI lifecycle prepayments (capital) | + |
| `REC0280` | Interest receivable | + |
| `REC0290` | Finance lease receivables | + |
| `REC0295` | Operating lease receivables | + |
| `REC0300` | VAT receivable | + |
| `REC0310` | Corporation and other taxes receivable | + |
| `REC0315` | Clinician pension tax provision reimbursement funding from NHSE | + |
| `REC0320` | Other receivables | + |
| `REC0325` | NHS charitable funds: receivables | + |
| `REC0330` | Total non-current receivables | + |
| `REC0335` | Total receivables | + |
| `REC0340` | Current | + |
| `REC0350` | Non-current | + |
| `REC1100` | Allowance for credit losses at 1 April - brought forward | + |
| `REC1110` | Prior period adjustments | +/- |
| `REC1120` | Allowance for credit losses at 1 April - restated | + |
| `REC1130` | At start of period for new FTs | +/- |
| `REC1140` | Transfer by absorption | +/- |
| `REC1150` | New allowances arising | + |
| `REC1160` | Changes in the calculation of existing allowances | +/- |
| `REC1170` | Reversals of allowances (where receivable is collected in-year) | - |
| `REC1180` | Utilisation of allowances (where receivable is written off) | - |
| `REC1190` | Changes arising following modification of contractual cash flows | +/- |
| `REC1200` | Foreign exchange and other changes | +/- |
| `REC1210` | Transfer to FT upon authorisation | +/- |
| `REC1220` | Total allowance for credit losses at 31 March | + |
| `REC1230` | Loss / (gain) recognised in expenditure | + |
| `REC0590` | Other assets | + |
| `REC0600` | Short term PFI receivable | + |
| `REC0610` | Total other current assets | + |
| `REC0620` | Net defined benefit pension scheme asset | + |
| `REC0630` | Other assets | + |
| `REC0640` | Total other non-current assets | + |
| `REC1400` | - not later than one year; | + |
| `REC1410` | - later than one year and not later than two years; | + |
| `REC1420` | - later than two years and not later than three years; | + |
| `REC1430` | - later than three years and not later than four years; | + |
| `REC1440` | - later than four years and not later than five years; | + |
| `REC1450` | - later than five years. | + |
| `REC1460` | Total future finance lease payments to be received | + |
| `REC1470` | Estimated value of unguaranteed residual interest | + |
| `REC1480` | Unearned interest income | - |
| `REC1490` | Allowance for uncollectable lease payments | - |
| `REC1500` | Net investment in lease (net lease receivable) | + |
| `REC1535` | Leased to other NHS providers | + |
| `REC1540` | Leased to other DHSC group bodies | + |
| `REC1250` | Finance lease receivables at 1 April 2023 - brought forward | + |
| `REC1290` | At start of period for New FTs | + |
| `REC1300` | Transfers by absorption | + |
| `REC1310` | Additions - new finance leases of assets previously held in PPE | + |
| `REC1311` | Additions - new finance subleases of previously held RoU assets | + |
| `REC1312` | Additions - finance subleases granted simultaneously with the headlease | + |
| `REC1320` | Interest arising (unwinding of discount) | + |
| `REC1330` | Remeasurements of lease receivables - taken to I&E | +/- |
| `REC1340` | Remeasurements of lease receivables - arising from movements in head lease liability passed on to sublessee | +/- |
| `REC1345` | Movement in allowances for uncollectable lease payments (amounts arising or reversed) | +/- |
| `REC1350` | Lease receipts (cash payments received) | - |
| `REC1360` | Derecognition due to lease termination | - |
| `REC1370` | Transfer to FT upon authorisation | + |
| `REC1380` | Finance lease receivables at 31 March 2024 | + |
| `REC1260` | Prior period adjustment | +/- |
| `REC1270` | Finance lease receivables at 1 April 2022 - restated | + |
| `REC1280` | Implementation of IFRS 16 on 1 April 2022 - subleases reclassified as finance leases | + |

## TAC19 CCE

| SubCode | Description | Sign |
|---------|-------------|------|
| `CCE0010` | At 1 April | + |
| `CCE0020` | Prior period adjustments | +/- |
| `CCE0030` | At 1 April (restated) | + |
| `CCE0040` | At start of period for new FTs | + |
| `CCE0050` | Transfers by absorption | + |
| `CCE0060` | Net change in year | +/- |
| `CCE0070` | Transfers to FT upon authorisation | +/- |
| `CCE0080` | At 31 March | + |
| `CCE0090` | Cash at commercial banks and in hand | + |
| `CCE0100` | Cash with the Government Banking Service | + |
| `CCE0110` | Deposits with the National Loan Fund | + |
| `CCE0120` | Other current investments | + |
| `CCE0130` | Total cash and cash equivalents as in SoFP | + |
| `CCE0140` | Bank overdrafts (GBS and commercial banks) | - |
| `CCE0150` | Drawdown in committed facility (non-DHSC) | - |
| `CCE0160` | Total cash and cash equivalents as in SoCF | +/- |
| `CCE0170` | Bank balances | + |
| `CCE0180` | Monies on deposit | + |
| `CCE0190` | Total third party assets | + |

## TAC20 Payables

| SubCode | Description | Sign |
|---------|-------------|------|
| `PAY0010` | Trade payables | + |
| `PAY0020` | Capital payables (including capital accruals) | + |
| `PAY0030` | Accruals (revenue costs only) | + |
| `PAY0035` | Annual leave accrual | + |
| `PAY0040` | Receipts in advance (including payments on account) | + |
| `PAY0041` | PFI lifecycle replacement received in advance | + |
| `PAY0050` | Social security costs | + |
| `PAY0060` | VAT payables | + |
| `PAY0070` | Other taxes payable | + |
| `PAY0080` | PDC dividend payable | + |
| `PAY0085` | Pension contributions payable | + |
| `PAY0110` | Other payables | + |
| `PAY0115` | NHS charitable funds: trade and other payables | + |
| `PAY0120` | Total current trade and other payables | + |
| `PAY0130` | Trade payables | + |
| `PAY0140` | Capital payables (including capital accruals) | + |
| `PAY0150` | Accruals (revenue costs only) | + |
| `PAY0160` | Receipts in advance (including payments on account) | + |
| `PAY0161` | PFI lifecycle replacement received in advance | + |
| `PAY0170` | VAT payables | + |
| `PAY0180` | Other taxes payable | + |
| `PAY0190` | Other payables | + |
| `PAY0195` | NHS charitable funds: trade and other payables | + |
| `PAY0200` | Total non-current trade and other payables | + |
| `PAY0205` | Total trade and other payables | + |
| `PAY0210` | Current | + |
| `PAY0220` | Non-current | + |
| `PAY0230` | - to buy out the liability for early retirements over 5 years | + |
| `PAY0240` | - number of cases | + |
| `PAY0340` | Deferred income: contract liability (IFRS 15) | + |
| `PAY0345` | Deferred grants | + |
| `PAY0350` | PFI: deferred income / credits | + |
| `PAY0360` | Lease incentives (relating to low value / short term leases only) | + |
| `PAY0362` | Deferred income: other (non-IFRS 15) | + |
| `PAY0365` | NHS charitable funds: other liabilities | + |
| `PAY0370` | Total other current liabilities | + |
| `PAY0380` | Deferred income: contract liability (IFRS 15) | + |
| `PAY0385` | Deferred grants | + |
| `PAY0390` | PFI: deferred income / credits | + |
| `PAY0400` | Lease incentives (relating to low value / short term leases only) | + |
| `PAY0405` | Deferred income: other (non-IFRS 15) | + |
| `PAY0415` | NHS charitable funds: other liabilities | + |
| `PAY0410` | Net defined benefit pension scheme liability | + |
| `PAY0420` | Total other non-current liabilities | + |
| `PAY0425` | Total other liabilities | + |
| `PAY0430` | Derivatives and embedded derivatives held at 'fair value through income and expenditure' | + |
| `PAY0440` | Other financial liabilities | + |
| `PAY0450` | Total | + |
| `PAY0460` | Derivatives and embedded derivatives held at 'fair value through income and expenditure' | + |
| `PAY0470` | Other financial liabilities | + |
| `PAY0480` | Total | + |

## TAC21 Borrowings

| SubCode | Description | Sign |
|---------|-------------|------|
| `SFP0570A` | Bank overdrafts - Government Banking Service | + |
| `SFP0570B` | Bank overdrafts - Commercial | + |
| `BOR0010` | NHS charitable funds: bank overdraft | + |
| `SFP0670C` | Drawdown in committed facility (non-DHSC) | + |
| `SFP0600` | Capital loans | + |
| `SFP0610` | Revenue support / working capital loans | + |
| `SFP0630` | Other loans (non-DHSC) | + |
| `SFP0590` | Lease liabilities | + |
| `SFP0580` | Obligations under PFI, LIFT or other service concession contracts (excl lifecycle) | + |
| `BOR0020` | NHS charitable funds: other current borrowings | + |
| `SFP0640` | Total current borrowings | + |
| `SFP0670` | Capital loans | + |
| `SFP0680` | Revenue support / working capital loans | + |
| `SFP0700` | Other loans (non-DHSC) | + |
| `SFP0660` | Lease liabilities | + |
| `SFP0650` | Obligations under PFI, LIFT or other service concession contracts (excl lifecycle) | + |
| `BOR0030` | NHS charitable funds: other non-current borrowings | + |
| `SFP0710` | Total non-current borrowings | + |
| `BOR0302` | - not later than one year; | + |
| `BOR0303` | - later than one year and not later than five years; | + |
| `BOR0304` | - later than five years. | + |
| `BOR0301` | Total gross future lease payments | + |
| `BOR0305` | Finance charges allocated to future periods | - |
| `BOR0310` | Net lease liabilities | + |
| `BOR0340` | Leased from other NHS providers | + |
| `BOR0345` | Leased from other DHSC group bodies | + |
| `BOR0440A` | Carrying value at 1 April 2023 - brought forward | + |
| `BOR0470` | Financing cash flows - principal | - |
| `BOR0480` | Financing cash flows - interest | - |
| `BOR0490` | At start of period for new FTs | + |
| `BOR0500` | Transfers by absorption | + |
| `BOR0510A` | Lease additions (recognition of a right of use asset) | + |
| `BOR0510B` | Lease additions (not recognised as RoU asset due to simultaneous sublease being created) - intra-government subleases | + |
| `BOR0510C` | Lease additions (not recognised as RoU asset due to simultaneous sublease being created) - external to government subleases | + |
| `BOR0515A` | Lease liability remeasurements (recognised in right of use asset) | +/- |
| `BOR0515B` | Lease liability remeasurements (relating to finance subleased asset - recognised in net investment in the sublease: ie sublease receivable) | +/- |
| `BOR0515C` | Lease liability remeasurements (relating to finance subleased asset - recognised in expenditure) (free text required) | +/- |
| `BOR0530` | Interest charge arising in year (application of effective interest rate) | + |
| `BOR0555` | Termination of lease | - |
| `BOR0520` | Business combinations (not absorption transfers) | + |
| `BOR0560` | Transfer to FT upon authorisation | - |
| `BOR0565` | Remeasurements - retranslation gains / (losses) on foreign operations | +/- |
| `BOR0570` | Other changes | +/- |
| `BOR0580` | Lease liabilities as at 31 March 2024 | + |
| `BOR0450` | Prior period adjustment | +/- |
| `BOR0460` | Carrying value at 1 April 2022 - restated | + |
| `BOR0465` | Impact of implementing IFRS 16 as at 1 April 2022 | + |
| `BOR0440` | Carrying value at 1 April 2023 - brought forward | + |
| `BOR0510` | Additions | + |
| `BOR0515` | Lease liability remeasurements | +/- |
| `BOR0517` | Remeasurement of PFI / other service concession liability resulting from change in index or rate (taken to financing costs) | +/- |
| `BOR0540` | Change in effective interest rate | +/- |
| `BOR0550` | Changes in fair values | +/- |

## TAC22 Provisions

| SubCode | Description | Sign |
|---------|-------------|------|
| `PRO0010` | Pensions - Early departure costs | + |
| `PRO0015` | Pensions - Injury benefits | + |
| `PRO0020` | Legal claims | + |
| `PRO0030` | Restructuring | + |
| `PRO0050` | Equal pay (including agenda for change) | + |
| `PRO0060` | Redundancy | + |
| `PRO0066` | Capitalised lease dilapidations - cost capitalised under IFRS 16 | + |
| `PRO0016` | 2019/20 clinicians' pension reimbursement | + |
| `PRO0070` | Other (Includes lease dilapidations previously charged to revenue) | + |
| `PRO0075` | Charitable fund provisions | + |
| `PRO0080` | Total | + |
| `SCI1350` | At 1 April 2023 - brought forward | + |
| `PRO0110` | At start of period for new FTs | + |
| `SCI1360` | Transfers by absorption | +/- |
| `SCI1370` | Change in discount rate | +/- |
| `SCI1380` | Arising during the year | + |
| `SCI1380A` | Arising during the year (relating to RoU assets derecognised under finance subleases only) | + |
| `SCI1390A` | Utilised during the year - accruals | - |
| `SCI1390B` | Utilised during the year - cash | - |
| `SCI1395` | Reclassified to liabilities held in disposal groups | - |
| `SCI1399` | Reversed unused - capital | - |
| `SCI1400` | Reversed unused - revenue | - |
| `SCI1410` | Unwinding of discount | +/- |
| `PRO0115` | Movement in charitable fund provisions | +/- |
| `PRO0120` | Transfer to FT upon authorisation | - |
| `SCI1420` | At 31 March 2024 | + |
| `PRO0130` | - not later than one year | + |
| `PRO0140` | - later than one year and not later than five years | + |
| `PRO0150` | - later than five years | + |
| `PRO0160` | Amount included in provisions of the NHS Resolution in respect of clinical negligence liabilities of the NHS provider | + |
| `PRO0170` | NHS Resolution legal claims | - |
| `PRO0180` | Employment tribunal and other employee related litigation | - |
| `PRO0190` | Redundancy | - |
| `PRO0200` | Other | - |
| `PRO0210` | Gross value of contingent liabilities | - |
| `PRO0220` | Amounts recoverable against liabilities | + |
| `PRO0230` | Net value of contingent liabilities | - |
| `PRO0240` | Net value of contingent assets | + |

## TAC24 On-SoFP PFI

| SubCode | Description | Sign |
|---------|-------------|------|
| `PFI0010` | Gross PFI, LIFT or other service concession SoFP obligation | + |
| `PFI0020` | - not later than one year; | + |
| `PFI0030` | - later than one year and not later than five years; | + |
| `PFI0040` | - later than five years. | + |
| `PFI0050` | Finance charges allocated to future periods | - |
| `PFI0060` | Net PFI, LIFT or other service concession SoFP obligation | + |
| `PFI0070` | - not later than one year; | + |
| `PFI0080` | - later than one year and not later than five years; | + |
| `PFI0090` | - later than five years. | + |
| `PFI0100` | Total future payments committed in respect of PFI, LIFT or other service concession arrangements | + |
| `PFI0110` | - not later than one year; | + |
| `PFI0120` | - later than one year and not later than five years; | + |
| `PFI0130` | - later than five years. | + |
| `CAP2530` | Number of schemes that the trust has (accounted for on-SoFP) as at 31 March 2024 | + |
| `CAP2660` | Unitary payment payable to service concession operator (total of all schemes) | + |
| `CAP2610` | - Interest charge | + |
| `CAP2600` | - Repayment of balance sheet obligation | + |
| `CAP2590` | - Service element (and other charges to operating expenditure excluding revenue lifecycle) | + |
| `CAP2620` | - Capital lifecycle maintenance | + |
| `CAP2630` | - Revenue lifecycle maintenance | + |
| `CAP2640` | - Contingent rent (should be nil in 2023/24 on an IFRS 16 basis) | + |
| `CAP2646` | - Addition to lifecycle prepayment - capital | + |
| `CAP2647` | - Addition to lifecycle prepayment - revenue | + |
| `CAP2680` | Amounts charged to revenue (free text required) | + |
| `CAP2690` | Amounts capitalised (free text required) | + |
| `CAP2700` | Total amount paid to service concession operator | + |
| `PFI0190` | PFI support income recognised in other operating income | + |
| `PFI0300` | Increase in PFI / LIFT and other service concession liabilities | - |
| `PFI0310` | Decrease in PDC dividend payable / increase in PDC dividend receivable | +/- |
| `PFI0320` | Increase in cash and cash equivalents (impact of PDC dividend only) | + |
| `PFI0330` | Impact on net assets as at 31 March 2024 | - |
| `PFI0340` | PFI liability remeasurement charged to finance costs |  |
| `PFI0350` | Increase in interest arising on PFI liability | - |
| `PFI0360` | Reduction in contingent rent (including amounts recognised in service costs) | + |
| `PFI0370` | Reduction in PDC dividend charge | + |
| `PFI0380` | Net impact on surplus / (deficit) | +/- |
| `PFI0390` | Adjustment to reserves for the cumulative retrospective impact on 1 April 2023 |  |
| `PFI0400` | Net impact on 2023/24 surplus / deficit | +/- |
| `PFI0410` | Impact on equity as at 31 March 2024 | +/- |
| `PFI0420` | Increase in cash outflows for capital element of PFI / LIFT | - |
| `PFI0430` | Decrease in cash outflows for financing element of PFI / LIFT (including amounts recorded in service costs) | + |
| `PFI0440` | Decrease in cash outflows for PDC dividend | + |
| `PFI0450` | Net impact on cash flows from financing activities | + |

## TAC25 Off-SoFP PFI

| SubCode | Description | Sign |
|---------|-------------|------|
| `PFI1000` | - not later than one year; | + |
| `PFI1010` | - later than one year and not later than five years; | + |
| `PFI1020` | - later than five years. | + |
| `PFI1030` | Total | + |
| `PFI1040` | Total charge to operating expenditure for off-SoFP schemes | + |
| `PFI1050` | Number of schemes that the trust has (accounted for off-SoFP) as at 31 March 2024 | + |

## TAC26 Pension

| SubCode | Description | Sign |
|---------|-------------|------|
| `PEN0010` | Present value of the defined benefit obligation at 1 April | - |
| `PEN0020` | Prior period adjustment | +/- |
| `PEN0030` | Present value of the defined benefit obligation at 1 April | - |
| `PEN0040` | At start of period for new FTs | - |
| `PEN0050` | Transfers by absorption | +/- |
| `PEN0060` | Current service cost | - |
| `PEN0070` | Interest cost | - |
| `PEN0080` | Contribution by plan participants | - |
| `PEN0090` | - Actuarial gains/(losses) | +/- |
| `PEN0100` | Benefits paid | + |
| `PEN0110` | Past service costs |  |
| `PEN0120` | Business combinations (transfers in/out) | +/- |
| `PEN0130` | Curtailments and settlements | + |
| `PEN0140` | Transferred to NHS foundation trust upon authorisation as FT | + |
| `PEN0150` | Present value of the defined benefit obligation at 31 March | - |
| `PEN0160` | Plan assets at fair value at 1 April | + |
| `PEN0170` | Prior period adjustment | +/- |
| `PEN0180` | Present value of plan assets at 1 April | + |
| `PEN0190` | At start of period for new FTs | + |
| `PEN0200` | Transfers by absorption | +/- |
| `PEN0210` | Interest income | + |
| `PEN0220` | - Return on plan assets (excludes any amounts already included in interest income above) | + |
| `PEN0230` | - Actuarial gains/(losses) | +/- |
| `PEN0240` | - Changes in the effect of limiting a net defined benefit asset to the asset ceiling (excluding amounts included in interest income/expense) | +/- |
| `PEN0250` | Contributions by the employer | + |
| `PEN0260` | Contributions by the plan participants | + |
| `PEN0270` | Benefits paid | - |
| `PEN0280` | Business combinations (transfers in/out) | +/- |
| `PEN0290` | Settlements | - |
| `PEN0300` | Transferred to NHS foundation trust upon authorisation as FT | - |
| `PEN0310` | Plan assets at fair value at 31 March | + |
| `PEN0320` | Plan surplus/(deficit) at 31 March | +/- |
| `PEN0330` | Present value of the defined benefit obligation | - |
| `PEN0340` | Plan assets at fair value | + |
| `PEN0370` | Net defined benefit (obligation)/asset recognised in the SoFP at 31 March | +/- |
| `PEN0372` | Fair value of any reimbursement right recognised as a separate asset on the SoFP | + |
| `PEN0375` | Total net (liability)/asset after the impact of reimbursement rights as at 31 March |  |
| `PEN0380` | Current service cost | +/- |
| `PEN0390` | Interest expense / income | +/- |
| `PEN0400` | Past service cost | +/- |
| `PEN0410` | Gains / (losses) on curtailment and settlement | +/- |
| `PEN0420` | Total net (charge)/gain recognised in SoCI |  |

## TAC27 Fin Inst

| SubCode | Description | Sign |
|---------|-------------|------|
| `FI0020` | Receivables (excluding non financial assets) - with DHSC group bodies | + |
| `FI0030` | Receivables (excluding non financial assets) - with other bodies | + |
| `FI0040` | Other investments / financial assets | + |
| `FI0050` | Cash and cash equivalents | + |
| `FI0055` | Consolidated NHS Charitable fund financial assets | + |
| `FI0060` | Total as at 31 March 2024 | + |
| `FI0081` | DHSC loans | + |
| `FI0082` | Other borrowings excluding lease and PFI liabilities | + |
| `FI0090` | Obligations under leases | + |
| `FI0100` | Obligations under PFI, LIFT and other service concession contracts | + |
| `FI0110` | Trade and other payables (excluding non financial liabilities) - with DHSC group bodies | + |
| `FI0120` | Trade and other payables (excluding non financial liabilities) - with other bodies | + |
| `FI0130` | Other financial liabilities | + |
| `FI0140` | IAS 37 provisions which are financial liabilities | + |
| `FI0145` | Consolidated NHS charitable fund financial liabilities | + |
| `FI0150` | Total as at 31 March 2024 | + |
| `FI0160` | In one year or less | + |
| `FI0170` | In more than one year but not more than five years | + |
| `FI0190` | In more than five years | + |
| `FI0200` | Total financial liabilities | + |
| `FI0220` | Receivables (excluding non financial assets) - with NHS and DHSC bodies | + |
| `FI0230` | Receivables (excluding non financial assets) - with other bodies | + |
| `FI0240` | Other investments / financial assets | + |
| `FI0250` | Cash and cash equivalents | + |
| `FI0255` | Consolidated NHS Charitable fund financial assets | + |
| `FI0260` | Total assets | + |
| `FI0275` | DHSC loans | + |
| `FI0280` | Other borrowings excluding lease and PFI liabilities | + |
| `FI0290` | Obligations under leases | + |
| `FI0300` | Obligations under PFI, LIFT and other service concession contracts | + |
| `FI0310` | Trade and other payables (excluding non financial liabilities) - with NHS and DHSC bodies | + |
| `FI0320` | Trade and other payables (excluding non financial liabilities) - with other bodies | + |
| `FI0330` | Other financial liabilities | + |
| `FI0340` | IAS 37 provisions which are financial liabilities | + |
| `FI0345` | Consolidated NHS charitable fund financial liabilities | + |
| `FI0350` | Total liabilities | + |

## TAC28 Disclosures

| SubCode | Description | Sign |
|---------|-------------|------|
| `OTD0010` | Property, plant and equipment | + |
| `OTD0020` | Intangible assets | + |
| `OTD0030` | Total | + |
| `OTD0031` | Commitments for leases not yet commenced to which the Trust is contractually committed | + |
| `OTD0032` | Variable lease payments (not dependent on an index or rate) | + |
| `OTD0033` | Extension options and termination options (not reasonably certain to be exercised) | + |
| `OTD0034` | Residual value guarantees | + |
| `OTD0035` | Other (unlocked on request) | + |
| `OTD0039` | Total | + |
| `OTD0040` | not later than 1 year | + |
| `OTD0050` | after 1 year and not later than 5 years | + |
| `OTD0060` | paid thereafter | + |
| `OTD0070` | Total | + |
| `OTD0080` | Value of transactions directly with board members (excluding salaries) | + |
| `OTD0090` | Value of transactions directly with key staff members (excluding salaries) | + |
| `OTD0100` | Charitable funds (where not consolidated) | + |
| `OTD0110` | Non-consolidated subsidiaries and associates / joint ventures | + |
| `OTD0120` | Other bodies or persons outside of the whole of government accounting boundary | + |
| `OTD0130` | Total value of transactions with related parties | + |
| `OTD0140` | Value of balances directly with board members (excluding salaries) | + |
| `OTD0150` | Value of balances directly with key staff members (excluding salaries) | + |
| `OTD0160` | Charitable funds (where not consolidated) | + |
| `OTD0170` | Non-consolidated subsidiaries and associates / joint ventures | + |
| `OTD0180` | Other bodies or persons outside of the whole of government accounting boundary | + |
| `OTD0190` | Value of credit loss allowances held against related parties (excludes salaries) | - |
| `OTD0210` | Total balances with related parties | + |
| `OTD0200` | Value of balances with related parties written off in year (excludes salaries) | - |
| `OTD0230` | Adjusted financial performance surplus/(deficit) (control total basis) | +/- |
| `OTD0240` | Remove impairments scoring to Departmental Expenditure Limit | +/- |
| `OTD0250` | Add back income for impact of 2022/23 post-accounts PSF reallocation | + |
| `OTD0255` | Add back non-cash element of On-SoFP pension scheme charges |  |
| `OTD0256` | Remove PPA adjustment | +/- |
| `OTD0257` | Add back incremental impact of IFRS 16 on PFI revenue costs in 2023/24 | +/- |
| `OTD0260` | IFRIC 12 breakeven adjustment | + |
| `OTD0270` | Breakeven duty financial performance surplus/(deficit) | +/- |
| `OTD0280` | Breakeven duty in-year financial performance | +/- |
| `OTD0290` | Breakeven duty cumulative position | +/- |
| `OTD0300` | Operating income (excluding consolidated charitable funds) | + |
| `OTD0310` | Cumulative breakeven position as a percentage of operating income |  |
| `OTD0330` | Property, Plant and Equipment | + |
| `OTD0340` | Intangible assets | + |
| `OTD0350` | Investment property | + |
| `OTD0360` | Right of use assets | + |
| `OTD0370` | Total gross capital expenditure | + |
| `OTD0380` | Property, Plant and Equipment | - |
| `OTD0390` | Intangible assets | - |
| `OTD0400` | Investment property | - |
| `OTD0410` | Right of use assets | - |
| `OTD0420` | Total disposals | - |
| `OTD0430` | Less: Donated, granted and peppercorn lease additions | - |
| `OTD0440` | Plus: Loss on disposal of peppercorn leased assets | + |
| `OTD0445` | Plus: Loss on disposal for capital grants in kind | + |
| `OTD0450` | Charge against Capital Resource Limit | +/- |
| `OTD0460` | Capital Resource Limit | + |
| `OTD0470` | Under / (over) spend against CRL | +/- |

## TAC29 Losses+SP

| SubCode | Description | Sign |
|---------|-------------|------|
| `LSP0010` | a. theft, fraud etc | + |
| `LSP0020` | b. overpayment of salaries etc. | + |
| `LSP0030` | c. other causes | + |
| `LSP0040` | 2. Fruitless payments and constructive losses | + |
| `LSP0050` | a. private patients | + |
| `LSP0060` | b. overseas visitors | + |
| `LSP0070` | c. other | + |
| `LSP0080` | a. theft, fraud etc | + |
| `LSP0090` | b. stores losses | + |
| `LSP0100` | c. other | + |
| `LSP0110` | Total losses | + |
| `LSP0120` | 5. Compensation under court order or legally binding arbitration award | + |
| `LSP0130` | 6. Extra contractual to contractors | + |
| `LSP0140` | a. loss of personal effects | + |
| `LSP0150` | b. clinical negligence with advice | + |
| `LSP0160` | c. personal injury with advice | + |
| `LSP0170` | d. other negligence and injury | + |
| `LSP0180` | e. other employment payments (should not include special severance payments which are disclosed below) | + |
| `LSP0190` | f. patient referrals outside the UK and EEA Guidelines | + |
| `LSP0200` | g. other | + |
| `LSP0210` | h. maladministration, no financial loss | + |
| `LSP0220` | 8. Special severance payments | + |
| `LSP0230` | 9. Extra statutory and regulatory | + |
| `LSP0240` | Total special payments | + |
| `LSP0250` | Total losses and special payments | + |
| `LSP0260` | 1. Losses of cash (including cases of fraud) | + |
| `LSP0270` | 2. Fruitless payments and constructive losses | + |
| `LSP0280` | 3. Bad debts and claims abandoned | + |
| `LSP0290` | 4. Damage to buildings, property etc. | + |
| `LSP0301` | 5. Compensation under legal obligation | + |
| `LSP0311` | 6. Extra contractual to contractors | + |
| `LSP0321` | 7. Ex gratia payments | + |
| `LSP0331` | 8. Special severance payments | + |
| `LSP0341` | 9. Extra statutory and regulatory | + |
| `LSP0360` | TOTAL GIFTS | + |
| `LSP0370` | Gift 1 | + |
| `LSP0380` | Gift 2 | + |
| `LSP0390` | Gift 3 | + |
| `LSP0400` | Gift 4 | + |
| `LSP0410` | Gift 5 | + |
