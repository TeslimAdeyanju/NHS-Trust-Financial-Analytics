# Analysis: seaborn notebooks and Shiny app

This folder is the analysis layer on top of the warehouse. It answers the questions a trust board or
finance director asks of the accounts, in two forms:

- **Notebooks** (seaborn): the written analysis, one question per notebook, with the reasoning next to
  each chart. They render on GitHub.
- **Shiny app** (Shiny for Python): an interactive explorer for analysts. Pick a year, a sector and a
  trust, and compare it with its peers. It sits beside the Power BI report as a second way into the
  same data.

| Notebook | Question |
| --- | --- |
| [01 Financial pressure by sector](notebooks/01_financial_pressure_by_sector.ipynb) | How many trusts are in deficit, in which sectors, and is it getting worse? |
| [02 Cost drivers](notebooks/02_cost_drivers.ipynb) | Has income kept up with costs, and which cost lines grew fastest? |
| [03 Peer benchmarking](notebooks/03_peer_benchmarking.ipynb) | Where does one trust sit within its own sector? |

## How the data gets here

Neither the notebooks nor the app connect to MySQL. One script reads the Gold views and writes two small
Parquet files, and everything in this folder reads those:

```text
nhs_gold.v_trust_annual_scorecard ─┐
nhs_gold.v_cash_flow               ├─► python/reporting/export_for_analysis.py ─► analysis/data/trust_year.parquet
nhs_gold.v_balance_sheet          ─┘
nhs_silver.fct_tac (TAC08 lines)  ───► python/reporting/export_for_analysis.py ─► analysis/data/expenditure_lines.parquet
                                                                                          │
                                       analysis/nhs_analysis.py (load, colours, £m) ◄─────┘
                                                 │
                                  notebooks/*.ipynb    app/app.py
```

`analysis/data/` is git-ignored like the rest of the generated data. Regenerate it after every pipeline
run. [`nhs_analysis.py`](nhs_analysis.py) holds the shared pieces: data loading, derived measures
(operating margin, current ratio, cash days), the fixed sector colours and the £000s to £m conversion.

## Run it

From the repository root, after the pipeline has loaded the warehouse:

```bash
pip install -r requirements.txt -r requirements-analysis.txt

# 1. Export the Parquet files (needs DB_PASSWORD, like every database script)
python python/reporting/export_for_analysis.py

# 2. Re-run the notebooks in place, so the committed charts match the data
jupyter nbconvert --to notebook --execute --inplace analysis/notebooks/*.ipynb

# 3. Start the app, then open http://127.0.0.1:8000
shiny run analysis/app/app.py
```

Notebook 03 benchmarks the trust named in the `TRUST_ORG_CODE` environment variable (an ODS code). Without
it, the notebook picks the trust with the lowest operating margin in the latest year.

The notebooks are committed with their outputs so the charts show on GitHub. Re-run step 2 whenever the
data changes, so the charts never go stale against the warehouse.

## Reading the results

- **Annual, actuals only.** TAC is an annual return, so there is no monthly, budget or forecast analysis.
- **Operating surplus** is the SoCI line `SCI0140A` as each trust reported it. It includes impairments,
  which are non-cash write-downs of buildings and equipment. NHS England's own performance measure
  excludes them, so a trust with a large operating deficit but a positive EBITDA margin has usually
  booked an impairment rather than run short of cash. The notebooks and the app show both margins side by
  side for this reason. The reconciliation to NHS England's figures is in the
  [financial reconciliation workpaper](../reports/nhs_financial_reconciliation.md).
- **Cost per WTE is left out.** The TAC09 whole-time-equivalent figures are incomplete for several trusts,
  most visibly the ambulance trusts, so pay as a share of income is used instead.
- **Units:** the data is in £000s and the charts show £m. No chart mixes the two.
- **Colours:** each sector keeps the same colour on every chart. Deficits are red and surpluses blue.
