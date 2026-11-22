# NHS provider financial reconciliation: 2021/22–2023/24

**Status:** Source/code audit and live three-statement validation completed; national accounting-basis reconciliation remains preliminary.

**Prepared:** 28 October 2026; live-run evidence updated 29 October 2026; closing-cash exceptions explained and rebuild evidence added 21 November 2026

**Scope:** NHS trusts and NHS foundation trusts. All monetary amounts below are £ million unless noted.

## 1. Purpose and conclusion

The portfolio's previous headline of an operating surplus of £1.6bn in 2021/22 and operating deficit of £1.6bn in 2023/24 was based on project-generated measures and cannot be compared directly with NHS England's consolidated **surplus / (deficit) before impairments and transfers**. These are different measures and may also differ in reporting population, consolidations and adjustments.

The official benchmark is:

| Financial year | Official balance before impairments and transfers (£m) | Providers in deficit (official basis) | Total providers | % in deficit |
| --- | ---: | ---: | ---: | ---: |
| 2021/22 | +562 | 74 | 215 | 34.4% |
| 2022/23 | −457 | 105 | 212 | 49.5% |
| 2023/24 | −2,312 | 136 | 211 | 64.5% |

**Source:** NHS England, consolidated provider accounts for [2021/22](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2021-to-2022), [2022/23](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2022-to-2023), and [2023/24](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2023-to-2024). The counts use the specific official definition *before impairments, transfers and consolidation of charitable funds*, which is not interchangeable with negative operating surplus.

## 2. Diagnostic comparison with historical project figures

The values below come from the previous project README and accompanying financial review. **They are not freshly reproduced from TAC data.**

| Year | Historical project operating surplus/(deficit), £m | NHS England official balance, £m | Arithmetic difference: project less official, £m | Project deficit trusts | Official deficit trusts |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2021/22 | +1,600 | +562 | +1,038 | 37 of 211 | 74 of 215 |
| 2022/23 | +148 | −457 | +605 | 85 of 207 | 105 of 212 |
| 2023/24 | −1,600 | −2,312 | +712 | 124 of 206 | 136 of 211 |

**Do not interpret these differences as unexplained accounting errors or recognised reconciling items.** They subtract different accounting measures, and the project figures are rounded. A proper bridge requires consistent gross operating balance, below-operating items, consolidation eliminations, and the precise reporting population.

## 3. Verified accounting basis and documented bridge

The NHS England 2022/23 consolidated provider accounts include a reconciliation from **segmental analysis** to the consolidated statement of comprehensive income. For 2022/23:

| Item | £m |
| --- | ---: |
| Operating surplus per segmental analysis | +1,273 |
| Inter-provider adjustment | −12 |
| Charitable funds consolidation | −1 |
| Operating surplus before impairments and transfers | **+1,260** |
| Net finance costs | −1,757 |
| Other items | +40 |
| Surplus/(deficit) before impairments and transfers | **−457** |

Thus, **+£1,260m operating surplus** and **−£457m before-impairments-and-transfers balance** are both possible for the same year. Their difference is mainly below-operating items. The 2022/23 report further reconciles −£457m to **−£1,515m** on the statutory statement basis after impairments/transfers.

The 2023/24 NHS England accounts report that application of IFRS 16 liability measurement principles to PFI and other service-concession liabilities increased the reported deficit by **£1,094m** and increased the count of deficit providers; absent that change, NHS England states **119** rather than 136 would have reported deficits. This is an accounting comparability issue, **not** evidence that £1,094m can simply be removed from every local project measure.

Primary official documents: [2022/23 accounts](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2022-to-2023) and [2023/24 accounts](https://www.gov.uk/government/publications/consolidated-nhs-provider-accounts-2023-to-2024).

## 4. What the code audit found

1. `sql/views/v_income_expenditure.sql` extracts `SCI0140A` into `operating_surplus_000s`, and separately extracts `SCI0240` into `net_surplus_000s`. It also constructs income from `SCI0100A + SCI0110A` and expenditure using `ABS(SCI0125A)`.
2. `sql/views/v_kpis.sql` defines `is_deficit = 1` whenever **operating** surplus is negative. That is *not* NHS England's official deficit-before-impairments-and-transfers classification.
3. `sql/views/v_trust_annual_scorecard.sql` repeats the operating-based `is_deficit` classification. The national trend SQL sums this flag, creating incomparable published provider counts.
4. `v_kpis` filters `ie.total_income_000s > 0`. This excludes records from the portfolio population and may change the count independently of organisational mergers and source coverage.
5. `MAX(CASE WHEN ...)` pivots require unique fact keys. The fresh load confirmed zero duplicate full-source rows and zero proposed fact-key collisions across all six workbooks.
6. `python/ingestion/load_tac_data.py` classifies CY/PY from MainCode and now resolves providers through deterministic normalised keys plus two reviewed aliases. The fresh run found zero ambiguous, duplicate or unmatched provider mappings.
7. Database scripts now require an environment-supplied password. Any password exposed by earlier history should still be rotated.
8. `v_kpis.sql` now applies parentheses consistently around the EBITDA numerator. Its RAG thresholds remain illustrative project bands rather than NHS regulatory ratings.

These observations originated from repository review. A subsequent fresh MySQL run loaded 2,210,974
facts for 215 trusts and confirmed complete three-statement coverage across 633 trust-years. A
from-scratch rebuild on 21 November 2026 reproduced the same facts and validation results.

### 4.1 Closing-cash exceptions: explained by bank overdrafts

**Conclusion:** the four SoFP-to-SoCF closing-cash exceptions are not data or pipeline errors. In every
case the difference is the trust's bank overdraft, which the two statements treat differently by
design. Once overdrafts are added back, no trust-year in the dataset has a closing-cash difference above
the £1,000 tolerance.

**Why the two figures differ.** The Statement of Financial Position (SoFP, `BAL1240`) reports cash and
cash equivalents gross, with any bank overdraft shown separately within borrowings. The Statement of Cash
Flows (SoCF, `SCF0355`) reports cash and cash equivalents *net* of overdrafts that are repayable on demand
and form part of cash management, as IAS 7 requires. TAC's own cash note, `TAC19 CCE`, records the bridge
explicitly:

> Total cash and cash equivalents as in SoFP (`CCE0130`)
> \+ Bank overdrafts (`CCE0140`) + Drawdown in committed facility (`CCE0150`)
> = Total cash and cash equivalents as in SoCF (`CCE0160`)

The project's check (`cash_cross_statement_residual_000s` in `v_statement_reconciliation`) compares
`BAL1240` with `SCF0355` directly, without the overdraft step, so any trust with an overdraft shows a
residual equal to that overdraft.

**The four exceptions** (£000):

| Provider/year | SoFP cash (`BAL1240`) | Bank overdraft (`CCE0140`) | SoFP cash after overdraft | SoCF closing cash (`SCF0355`) | Residual now reported | Residual after bridge |
|---|---:|---:|---:|---:|---:|---:|
| Cambridge University Hospitals NHS Foundation Trust — 2021/22 | 224,151 | −135 | 224,016 | 224,016.35 | 134.65 | −0.35 |

| Royal Cornwall Hospitals NHS Trust — 2022/23 | 24,620 | −3 | 24,617 | 24,617 | 3.00 | 0.00 |
| Royal Cornwall Hospitals NHS Trust — 2023/24 | 16,868 | −5 | 16,863 | 16,863 | 5.00 | 0.00 |
| Tees, Esk and Wear Valleys NHS Foundation Trust — 2023/24 | 60,198 | −270 | 59,928 | 59,928.01 | 269.99 | −0.01 |

In words: Tees, Esk and Wear Valleys had an overdraft of £270,000 at 31 March 2024, Cambridge
University Hospitals one of £135,000 at 31 March 2022, and Royal Cornwall Hospitals overdrafts of £3,000
and £5,000 at 31 March 2023 and 2024. The remaining differences of about £348 and £6 are rounding: the SoCF
lines for those two trusts carry fractional £000 values while the SoFP and cash note are in whole
thousands.

**Population-wide test.** The bridge was applied to all 633 trust-years, not only these four:

| Test (all 633 trust-years) | Result |
|---|---:|
| Trust-years with SoFP and SoCF cash both present | 633 |
| Trust-years reporting a bank overdraft (`CCE0140` ≠ 0) | 5 |
| Trust-years drawing on a committed facility (`CCE0150` ≠ 0) | 0 |
| Exceptions above £1,000 — current check (`BAL1240 − SCF0355`) | 4 |
| Exceptions above £1,000 — after adding overdraft and facility lines | **0** |
| Largest absolute difference after the bridge | £926 (0.92561 in £000) |

The fifth overdraft — Royal Cornwall Hospitals, 2021/22, £1,000 — produced a residual of exactly £1,000,
which the current check passes because its tolerance is "more than £1,000".

**A trap in the cash note.** `TAC19 CCE` has two value columns, `A19CY01` and `A19CY02`. In 127
trust-years (mostly foundation trusts) the trust reported its cash across both, so `A19CY01` alone
disagrees with the SoCF; the two columns summed agree in every case. Any query using the note must sum
both columns. No overdraft or facility amount appears in `A19CY02` in this dataset, but a corrected check
should still sum both.

**Recommended correction (not yet applied).** Change the closing-cash residual in
`sql/views/v_statement_reconciliation.sql` to add the overdraft and committed-facility lines from
`TAC19 CCE` (both columns) before comparing with `SCF0355`:

```sql
-- SoFP cash, plus overdrafts and committed-facility drawdowns (both TAC19 columns), less SoCF closing cash
sofp.cash_and_cash_equivalents_000s
  + COALESCE(cce.overdrafts_and_facility_000s, 0)
  - socf.closing_cash_000s
```

With that change the validation check would pass for all 633 trust-years. Until it is made, the check will
continue to report these four trust-years as a non-critical warning. That warning is expected and
explained, not an open accounting question.

**Reproduce:**

```sql
WITH c AS (
  SELECT org_code, financial_year,
         MAX(CASE WHEN sub_code = 'BAL1240' THEN total_000s END)                     AS sofp_cash,
         MAX(CASE WHEN sub_code = 'SCF0355' THEN total_000s END)                     AS socf_cash,
         SUM(CASE WHEN sub_code IN ('CCE0140', 'CCE0150') THEN total_000s END)       AS overdrafts
  FROM nhs_silver.fct_tac
  WHERE sub_code IN ('BAL1240', 'SCF0355', 'CCE0140', 'CCE0150')
  GROUP BY org_code, financial_year
)
SELECT org_code, financial_year, sofp_cash, overdrafts, socf_cash,
       sofp_cash - socf_cash                AS residual_now,
       sofp_cash + overdrafts - socf_cash   AS residual_after_bridge
FROM c
WHERE ABS(sofp_cash - socf_cash) > 1 OR ABS(sofp_cash + overdrafts - socf_cash) > 1
ORDER BY ABS(sofp_cash - socf_cash) DESC;
```

## 5. Reconciliation workpaper template

Complete this table for **each** year, in the same units and for the same included providers. Use `NULL`/not available rather than filling gaps with official numbers.

| Line | Description | 2021/22 | 2022/23 | 2023/24 |
| --- | --- | --- | --- | --- |
| A | TAC gross operating result, selected statutory provider population | Pending | Pending | Pending |
| B | Adjustments for inter-provider transactions | Pending | Pending | Pending |
| C | Charitable funds consolidation adjustments | Pending | Pending | Pending |
| D = A+B+C | Consolidated operating surplus/(deficit), before impairments/transfers | Pending | Pending | Pending |
| E | Finance income/expense and public dividend capital items | Pending | Pending | Pending |
| F | Other gains/losses and relevant statutory items | Pending | Pending | Pending |
| G = D+E+F | Reconstructed surplus/(deficit) before impairments/transfers | Pending | Pending | Pending |
| H | Official published balance | **+562** | **−457** | **−2,312** |
| I = G−H | Reconciliation difference | Pending | Pending | Pending |
| J | Official provider deficit count | 74 | 105 | 136 |
| K | Reconstructed provider deficit count on identical basis | Pending | Pending | Pending |

The line-item mapping for E and F requires review against the full accounting notes; a simplistic `SCI0240` total may include items that should be excluded for the benchmark. NHS England's consolidated adjustments may not be directly derivable from individual TAC extracts, so any remaining difference must be documented, not forced to zero.

## 6. Reproducible diagnostic SQL (read-only)

Run the queries below against your populated MySQL environment. They generate **preliminary TAC summaries**, **not** the official consolidated benchmark.

```sql
-- A. Coverage and missing values for each reporting year
SELECT financial_year,
       COUNT(DISTINCT org_code) AS trusts,
       COUNT(*) AS records,
       SUM(operating_surplus_000s IS NULL) AS missing_operating,
       SUM(net_surplus_000s IS NULL) AS missing_net
FROM nhs_gold.v_income_expenditure
GROUP BY financial_year ORDER BY financial_year;

-- B. Keep operating and statutory net measures separate
SELECT financial_year,
       COUNT(DISTINCT org_code) AS included_trusts,
       ROUND(SUM(operating_surplus_000s)/1000, 1) AS operating_m,
       ROUND(SUM(net_surplus_000s)/1000, 1) AS net_m,
       SUM(operating_surplus_000s < 0) AS operating_deficit_trusts,
       SUM(net_surplus_000s < 0) AS net_deficit_trusts
FROM nhs_gold.v_income_expenditure
GROUP BY financial_year ORDER BY financial_year;

-- C. Detect duplicate TAC keys requiring investigation
SELECT financial_year, org_code, worksheet_name, sub_code,
       COUNT(*) AS rows_per_key
FROM nhs_silver.fct_tac
WHERE worksheet_name = 'TAC02 SoCI'
  AND sub_code IN ('SCI0140A','SCI0240')
GROUP BY financial_year, org_code, worksheet_name, sub_code
HAVING COUNT(*) > 1
ORDER BY rows_per_key DESC;
```

The final query intentionally surfaces duplicates for review: do not automatically delete them without distinguishing legitimate data dimensions.

## 7. Required completion criteria

- [x] Load and checksum the six annual TAC spreadsheets for the three financial years; source URLs and publication metadata remain documented separately.
- [ ] Confirm the exact NHS provider population per year and reconcile organisational changes, omissions and filters.
- [ ] Confirm `SCI0140A`, `SCI0240` and other relevant TAC definitions and their sign conventions.
- [x] Re-run ingestion and verify `CY` selection, duplicate keys, organisational mappings and missing statement measures.
- [x] Export per-provider, per-year SoCI, SoFP, SoCF and statement-reconciliation components.
- [x] Explain the four SoFP-to-SoCF closing-cash exceptions (bank overdrafts; see section 4.1).
- [ ] Apply the overdraft bridge to `v_statement_reconciliation` so the closing-cash check passes on the correct basis.
- [ ] Obtain official consolidation/inter-provider/charitable adjustment amounts from the annual reports and reconcile the statutory lines.
- [ ] Explain every material variance and year-on-year accounting-policy difference.
- [ ] Reconcile the deficit flag to the **same** official measure and provider population.
- [ ] Correct source code and KPI definitions on a separate reviewed branch once root causes are established.
- [ ] Only then update the financial review, project README and eventual Power BI dashboard with independently verified project results.

## 8. Evidence classification

**Verified:** Official NHS England benchmark figures and 2022/23 published accounting bridge; the code-level mapping and classification logic described above; the cause of all four SoFP-to-SoCF closing-cash exceptions (bank overdrafts), tested across all 633 trust-years.

**Previously reported, not reproduced:** Project `+£1.6bn / +£148m / −£1.6bn` operating values, project trust counts and project income/expenditure table.

**Not yet possible to verify:** Exact numerical reconciliation differences on a like-for-like basis, provider-level variances, full consolidation journals and final independently reproduced 2021/22–2023/24 results.

This report is an audit-ready **starting workpaper**, not a signed-off reconciliation.
