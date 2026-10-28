# NHS Trust Financial Analytics

> An NHS financial analytics project transforming published Trust Accounts Consolidation data into comparable financial measures and reporting outputs for trusts in England.

**Period:** 2021/22 to 2023/24 | **Scope:** NHS Trusts and Foundation Trusts | **Tools:** Python, MySQL, SQL, Power BI and DAX

## Project overview

This project examines the financial sustainability of NHS providers by combining annual accounts data, standardising financial measures and comparing performance across organisations and reporting years.

It includes a six-stage data pipeline, SQL-based financial analysis, audit and validation logic, and a Power BI reporting model. The detailed business context, implementation decisions and technical evidence are maintained in [Project Documentation](PROJECT_DOCUMENTATION.md).

## Key findings

| Indicator | 2021/22 | 2022/23 | 2023/24 |
| --- | ---: | ---: | ---: |
| Total provider income | £110.3bn | £118.4bn | £129.2bn |
| Total provider expenditure | £108.7bn | £118.2bn | £130.8bn |
| Reported operating surplus / (deficit) | +£1.6bn | +£148m | **−£1.6bn** |
| Trusts reporting a deficit | 37 of 211 | 85 of 207 | **124 of 206** |

**Headline:** In the project's historical analysis, the provider sector shifted from a reported £1.6bn operating surplus to a £1.6bn deficit over two years. In 2023/24, 124 of 206 trusts were reported as being in deficit.

Figures are taken from the project's existing analysis, not newly audited in this README revision. For calculations, assumptions, financial conventions and interpretation, read the [2023/24 Financial Review](reports/nhs_sector_financial_review_2324.md).

## Power BI dashboard

**Dashboard publication pending.** The repository includes the Power BI model reference, report page specifications and DAX measure definitions, but no published report or report-page screenshot is available to link here yet.

The planned report presentation includes an executive summary, income and expenditure analysis, cost pressures, trust benchmarking and workforce measures. Once the dashboard is ready, this section will show a genuine screenshot and a verified report link.

[Power BI setup guide](power_bi/setup_guide.md) | [DAX measures](power_bi/dax_measures.md)

## Data architecture

![NHS Trust financial analytics pipeline](docs/images/pipeline_architecture.png)

The workflow takes published NHS England accounts workbooks through Python ingestion and MySQL staging, prepares analytical views and exports data for Power BI. The detailed schema, data checks, source mapping and implementation choices are explained in [Project Documentation](PROJECT_DOCUMENTATION.md).

## Documentation and reproducibility

| Resource | Contents |
| --- | --- |
| [Project Documentation](PROJECT_DOCUMENTATION.md) | Business case, source data, methodology, architecture and implementation |
| [2023/24 Financial Review](reports/nhs_sector_financial_review_2324.md) | Detailed findings and financial interpretation |
| [Power BI Setup Guide](power_bi/setup_guide.md) | Relationships and proposed report pages |
| [DAX Measures](power_bi/dax_measures.md) | Financial reporting calculations |
| [NHS KPI Definitions](agent_docs/kpi_definitions.md) | Definitions and reporting conventions |
| [Development Notes](notebook/) | Stage-by-stage implementation history |

**Source:** [NHS England Trust Accounts Consolidation publications](https://www.england.nhs.uk/financial-accounting-reporting-systems/nhs-england-finance-returns-publications-guidance/trust-accounts-consolidation-tac/).

To reproduce the pipeline, obtain the corresponding annual TAC workbooks, configure Python 3.11+ and MySQL 8+, and follow the documented ingestion, validation and export steps in [Project Documentation](PROJECT_DOCUMENTATION.md). The underlying source workbooks and generated exports are not committed to this repository.

## Author

**Teslim Adeyanju** | [Portfolio](https://adeyanjuteslim.co.uk) | [LinkedIn](https://www.linkedin.com/in/adeyanjuteslimuthman)

[Previous README (full archive)](docs/readme-history.md)
