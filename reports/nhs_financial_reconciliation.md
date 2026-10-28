# NHS provider financial reconciliation: 2021/22–2023/24

**Status:** Preliminary accounting-basis reconciliation and source/code audit. **Not** a completed row-by-row reconciliation against the six TAC workbooks or a live MySQL run.  
**Prepared:** 28 October 2026  
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
5. `v_income_expenditure` uses `MAX(CASE WHEN ...)` by provider/year without demonstrating uniqueness by TAC data type, source file or MainCode. Check for duplicate records and unintended aggregation loss.
6. `python/ingestion/load_tac_data.py` infers CY/PY from the MainCode using a string test and joins providers by name in its ingestion workflow. These must be checked against year-specific source schemas and ODS identifiers.
7. The ingestion script contains a hard-coded database password. Move credentials to environment variables and rotate the password **if used**. This is an immediate hygiene issue independent of the reconciliation.
8. `v_kpis.sql`'s EBITDA RAG CASE expression lacks parentheses around the whole numerator; due to operator precedence it is not equivalent to the correctly calculated `ebitda_margin_pct`. Separately review KPI definitions and thresholds before dashboard publication.

These observations were verified from repository source files; no live database access was available.

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

- [ ] Obtain six original annual NHS England TAC spreadsheets for the three financial years and document filenames, source URLs, versions and checksums.
- [ ] Confirm the exact NHS provider population per year and reconcile organisational changes, omissions and filters.
- [ ] Confirm `SCI0140A`, `SCI0240` and other relevant TAC definitions and their sign conventions.
- [ ] Re-run ingestion, check `CY` selection, duplicate keys, organisational mappings and missing measures.
- [ ] Export per-provider, per-year components and join against the published basis.
- [ ] Obtain official consolidation/inter-provider/charitable adjustment amounts from the annual reports and reconcile the statutory lines.
- [ ] Explain every material variance and year-on-year accounting-policy difference.
- [ ] Reconcile the deficit flag to the **same** official measure and provider population.
- [ ] Correct source code and KPI definitions on a separate reviewed branch once root causes are established.
- [ ] Only then update the financial review, project README and eventual Power BI dashboard with independently verified project results.

## 8. Evidence classification

**Verified:** Official NHS England benchmark figures and 2022/23 published accounting bridge; the code-level mapping and classification logic described above.

**Previously reported, not reproduced:** Project `+£1.6bn / +£148m / −£1.6bn` operating values, project trust counts and project income/expenditure table.

**Not yet possible to verify:** Exact numerical reconciliation differences on a like-for-like basis, provider-level variances, full consolidation journals and final independently reproduced 2021/22–2023/24 results.

This report is an audit-ready **starting workpaper**, not a signed-off reconciliation.
