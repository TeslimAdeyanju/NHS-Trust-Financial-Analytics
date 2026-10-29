-- Canonical Gold-view deployment order.
-- Run from the repository root with client commands enabled so SOURCE paths resolve:
--   mysql --commands -u root -p < sql/schema/deploy_gold_views.sql

SOURCE sql/views/v_income_expenditure.sql;
SOURCE sql/views/v_profit_and_loss.sql;
SOURCE sql/views/v_balance_sheet.sql;
SOURCE sql/views/v_cash_flow.sql;
SOURCE sql/views/v_expenditure_breakdown.sql;
SOURCE sql/views/v_workforce.sql;
SOURCE sql/views/v_kpis.sql;
SOURCE sql/views/v_trust_annual_scorecard.sql;
SOURCE sql/views/v_statement_reconciliation.sql;
