-- NHS Trust Financial Analytics
-- Schemas: nhs_bronze (raw landing) -> nhs_silver (conformed dims/fact) -> nhs_gold (analytical views)
-- All monetary values in £000s unless stated otherwise
-- Source: NHS England TAC (Trust Accounts Consolidation) data publications
--
-- This is a Postgres portability reference only -- not deployed or queried by anything in
-- python/ or power_bi/. sql/schema/create_tables_mysql.sql is canonical: it carries the full
-- ~1,000-row dim_subcode seed (all 28 real TAC worksheets) and the v_profit_and_loss /
-- v_balance_sheet views, neither of which is duplicated here.

-- ============================================================
-- SCHEMAS
-- ============================================================

CREATE SCHEMA IF NOT EXISTS nhs_bronze;
CREATE SCHEMA IF NOT EXISTS nhs_silver;
CREATE SCHEMA IF NOT EXISTS nhs_gold;


-- ============================================================
-- STAGING TABLES (1:1 with raw source files)
-- ============================================================

-- Raw TAC data — mirrors the "All data" sheet exactly
DROP TABLE IF EXISTS nhs_bronze.stg_tac_raw;
CREATE TABLE nhs_bronze.stg_tac_raw (
    organisation_name   VARCHAR(300)    NOT NULL,
    worksheet_name      VARCHAR(50)     NOT NULL,
    table_id            SMALLINT        NOT NULL,
    main_code           VARCHAR(20)     NOT NULL,
    row_number          SMALLINT        NOT NULL,
    sub_code            VARCHAR(20)     NOT NULL,
    total               NUMERIC(14, 0)  NOT NULL, -- £000s
    -- load metadata
    source_file         VARCHAR(200)    NOT NULL, -- e.g. TAC_NHS_trusts_2023-24.xlsx
    trust_type          VARCHAR(20)     NOT NULL, -- NHS_TRUST | FOUNDATION_TRUST
    financial_year      CHAR(7)         NOT NULL, -- e.g. 2023/24
    year_type           CHAR(2)         NOT NULL, -- CY (current year) | PY (prior year)
    load_ts             TIMESTAMPTZ     DEFAULT now()
);

-- Raw provider list — mirrors the "List of Providers" sheet
DROP TABLE IF EXISTS nhs_bronze.stg_provider_list;
CREATE TABLE nhs_bronze.stg_provider_list (
    organisation_name   VARCHAR(300)    NOT NULL,
    org_code            CHAR(3)         NOT NULL,
    region              VARCHAR(100),
    sector              VARCHAR(50),
    comments            TEXT,
    source_file         VARCHAR(200)    NOT NULL,
    trust_type          VARCHAR(20)     NOT NULL, -- NHS_TRUST | FOUNDATION_TRUST
    financial_year      CHAR(7)         NOT NULL,
    load_ts             TIMESTAMPTZ     DEFAULT now()
);


-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- dim_trust: one row per provider
DROP TABLE IF EXISTS nhs_silver.dim_trust CASCADE;
CREATE TABLE nhs_silver.dim_trust (
    org_code            CHAR(3)         PRIMARY KEY,
    organisation_name   VARCHAR(300)    NOT NULL,
    trust_type          VARCHAR(20)     NOT NULL,    -- NHS_TRUST | FOUNDATION_TRUST
    sector              VARCHAR(50),                 -- Acute | Mental Health | Community | Ambulance | Specialist
    region              VARCHAR(100),
    is_foundation       BOOLEAN         NOT NULL DEFAULT FALSE,
    first_year_seen     CHAR(7),                     -- e.g. 2021/22
    last_year_seen      CHAR(7),                     -- e.g. 2023/24
    updated_ts          TIMESTAMPTZ     DEFAULT now()
);

-- dim_financial_year: one row per NHS financial year
DROP TABLE IF EXISTS nhs_silver.dim_financial_year CASCADE;
CREATE TABLE nhs_silver.dim_financial_year (
    financial_year      CHAR(7)         PRIMARY KEY, -- e.g. 2023/24
    start_date          DATE            NOT NULL,    -- 1 April
    end_date            DATE            NOT NULL,    -- 31 March
    year_label_short    CHAR(5)         NOT NULL,    -- e.g. 23/24
    is_complete         BOOLEAN         NOT NULL DEFAULT TRUE -- FALSE if year still in progress
);

-- Seed dim_financial_year
INSERT INTO nhs_silver.dim_financial_year VALUES
    ('2019/20', '2019-04-01', '2020-03-31', '19/20', TRUE),
    ('2020/21', '2020-04-01', '2021-03-31', '20/21', TRUE),
    ('2021/22', '2021-04-01', '2022-03-31', '21/22', TRUE),
    ('2022/23', '2022-04-01', '2023-03-31', '22/23', TRUE),
    ('2023/24', '2023-04-01', '2024-03-31', '23/24', TRUE);

-- dim_worksheet: reference for TAC schedule names and purposes
DROP TABLE IF EXISTS nhs_silver.dim_worksheet CASCADE;
CREATE TABLE nhs_silver.dim_worksheet (
    worksheet_name      VARCHAR(50)     PRIMARY KEY,
    schedule_title      VARCHAR(200)    NOT NULL,
    category            VARCHAR(50)     NOT NULL,   -- INCOME | EXPENDITURE | BALANCE_SHEET | CASH_FLOW | STAFF | OTHER
    sub_code_prefix     VARCHAR(10)
);

INSERT INTO nhs_silver.dim_worksheet VALUES
    ('TAC02 SoCI',          'Statement of Comprehensive Income',            'SUMMARY',          'SCI'),
    ('TAC03 SoFP',          'Statement of Financial Position',              'BALANCE_SHEET',    'BAL'),
    ('TAC04 SOCIE',         'Statement of Changes in Equity',               'EQUITY',           'SCE'),
    ('TAC05 SoCF',          'Statement of Cash Flows',                      'CASH_FLOW',        'SCF'),
    ('TAC06 Op Inc 1',      'Operating Income from Patient Care',           'INCOME',           'INC0'),
    ('TAC07 Op Inc 2',      'Other Operating Income',                       'INCOME',           'INC1'),
    ('TAC08 Op Exp',        'Operating Expenditure',                        'EXPENDITURE',      'EXP'),
    ('TAC09 Staff',         'Staff Costs and WTE Numbers',                  'STAFF',            'STA'),
    ('TAC11 Finance & other','Finance Income, Expense and PDC',             'FINANCE',          'FIN'),
    ('TAC12 Impairment',    'Asset Impairments',                            'OTHER',            'IMP'),
    ('TAC13 Intangibles',   'Intangible Assets',                            'BALANCE_SHEET',    'INT'),
    ('TAC14 PPE',           'Property Plant and Equipment',                 'BALANCE_SHEET',    'PPE'),
    ('TAC14A RoU Assets',   'Right-of-Use Assets (IFRS 16)',                'BALANCE_SHEET',    'ROU'),
    ('TAC18 Receivables',   'Receivables and Debtors',                      'BALANCE_SHEET',    'REC'),
    ('TAC19 CCE',           'Cash and Cash Equivalents',                    'BALANCE_SHEET',    'CCE'),
    ('TAC20 Payables',      'Payables and Creditors',                       'BALANCE_SHEET',    'PAY'),
    ('TAC22 Provisions',    'Provisions for Liabilities',                   'BALANCE_SHEET',    'PRV'),
    ('TAC28 Disclosures',   'Statutory Disclosures (NHS Trusts only)',       'OTHER',            'DIS'),
    ('TAC29 Losses+SP',     'Losses and Special Payments',                  'OTHER',            'LSP');

-- dim_subcode: reference for line item codes (sourced from illustrative file)
DROP TABLE IF EXISTS nhs_silver.dim_subcode CASCADE;
CREATE TABLE nhs_silver.dim_subcode (
    sub_code            VARCHAR(20)     PRIMARY KEY,
    worksheet_name      VARCHAR(50)     REFERENCES nhs_silver.dim_worksheet(worksheet_name),
    description         VARCHAR(300)    NOT NULL,
    expected_sign       CHAR(3),                    -- '+' | '-' | '+/-'
    unit                VARCHAR(10)     NOT NULL DEFAULT '£000',  -- '£000' | 'No.' | '%'
    is_subtotal         BOOLEAN         NOT NULL DEFAULT FALSE,
    analytics_category  VARCHAR(30)     -- PATIENT_INCOME | OTHER_INCOME | PAY | NON_PAY | STAFF_WTE | BALANCE_SHEET
);

-- Key subcodes for analytics (extend as needed)
INSERT INTO nhs_silver.dim_subcode VALUES
    -- SoCI summary
    ('SCI0100A', 'TAC02 SoCI', 'Operating income from patient care activities',       '+',   '£000', TRUE,  'PATIENT_INCOME'),
    ('SCI0110A', 'TAC02 SoCI', 'Other operating income',                              '+',   '£000', TRUE,  'OTHER_INCOME'),
    ('SCI0125A', 'TAC02 SoCI', 'Operating expenses (total)',                          '-',   '£000', TRUE,  'TOTAL_EXPENDITURE'),
    ('SCI0140A', 'TAC02 SoCI', 'Operating surplus / (deficit)',                       '+/-', '£000', TRUE,  'OPERATING_SURPLUS'),
    ('SCI0150',  'TAC02 SoCI', 'Finance income',                                      '+',   '£000', FALSE, NULL),
    ('SCI0160',  'TAC02 SoCI', 'Finance expense',                                     '-',   '£000', FALSE, NULL),
    ('SCI0170',  'TAC02 SoCI', 'PDC dividend expense',                                '-',   '£000', FALSE, NULL),
    ('SCI0240',  'TAC02 SoCI', 'Surplus / (deficit) for the year',                   '+/-', '£000', TRUE,  'NET_SURPLUS'),
    ('SOC0190',  'TAC02 SoCI', 'Total comprehensive income / (expense)',              '+/-', '£000', TRUE,  NULL),
    -- Patient care income (by nature)
    ('INC0197',  'TAC06 Op Inc 1', 'API income - Variable (acute)',                   '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0198',  'TAC06 Op Inc 1', 'API income - Fixed (acute)',                      '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0200',  'TAC06 Op Inc 1', 'High cost drugs income from commissioners',       '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0210',  'TAC06 Op Inc 1', 'Other NHS clinical income (acute)',               '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0231',  'TAC06 Op Inc 1', 'API income (mental health)',                      '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0302',  'TAC06 Op Inc 1', 'API income (community)',                          '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0330',  'TAC06 Op Inc 1', 'Private patient income',                          '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0332',  'TAC06 Op Inc 1', 'Pay award central funding',                       '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0340',  'TAC06 Op Inc 1', 'Other clinical income',                           '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC0350',  'TAC06 Op Inc 1', 'Total income from patient care activities',       '+',   '£000', TRUE,  'PATIENT_INCOME'),
    -- Patient care income (by source)
    ('INC1100',  'TAC06 Op Inc 1', 'Patient care income from NHS England',            '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC1115',  'TAC06 Op Inc 1', 'Patient care income from Integrated Care Boards', '+',  '£000', FALSE, 'PATIENT_INCOME'),
    ('INC1140',  'TAC06 Op Inc 1', 'Patient care income from Local Authorities',      '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC1170',  'TAC06 Op Inc 1', 'Non-NHS: private patients',                       '+',   '£000', FALSE, 'PATIENT_INCOME'),
    ('INC1220',  'TAC06 Op Inc 1', 'Total income from patient care (by source)',      '+',   '£000', TRUE,  'PATIENT_INCOME'),
    -- Other operating income
    ('INC1230A', 'TAC07 Op Inc 2', 'Research and development income (IFRS 15)',       '+',   '£000', FALSE, 'OTHER_INCOME'),
    ('INC1240A', 'TAC07 Op Inc 2', 'Education and training income',                   '+',   '£000', FALSE, 'OTHER_INCOME'),
    ('INC1280A', 'TAC07 Op Inc 2', 'Non-patient care services to other bodies',       '+',   '£000', FALSE, 'OTHER_INCOME'),
    ('INC1360',  'TAC07 Op Inc 2', 'Total other operating income',                    '+',   '£000', TRUE,  'OTHER_INCOME'),
    ('INC1365',  'TAC07 Op Inc 2', 'Total operating income',                          '+',   '£000', TRUE,  'TOTAL_INCOME'),
    -- Operating expenditure
    ('EXP0100',  'TAC08 Op Exp',   'Purchase of healthcare from NHS bodies',          '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0110',  'TAC08 Op Exp',   'Purchase of healthcare from non-NHS bodies',      '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0130',  'TAC08 Op Exp',   'Staff and executive directors costs',             '+',   '£000', FALSE, 'PAY'),
    ('EXP0140',  'TAC08 Op Exp',   'Non-executive directors costs',                   '+',   '£000', FALSE, 'PAY'),
    ('EXP0150',  'TAC08 Op Exp',   'Supplies and services - clinical',                '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0160',  'TAC08 Op Exp',   'Supplies and services - general',                 '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0170',  'TAC08 Op Exp',   'Drugs costs',                                     '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0190',  'TAC08 Op Exp',   'Consultancy',                                     '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0200',  'TAC08 Op Exp',   'Establishment costs',                             '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0210',  'TAC08 Op Exp',   'Premises - business rates',                       '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0220',  'TAC08 Op Exp',   'Premises - other',                                '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0230A', 'TAC08 Op Exp',   'Transport - business travel',                    '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0230B', 'TAC08 Op Exp',   'Transport - other including patient travel',     '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0240',  'TAC08 Op Exp',   'Depreciation',                                    '+',   '£000', FALSE, 'NON_PAY_EXCL_EBITDA'),
    ('EXP0250',  'TAC08 Op Exp',   'Amortisation',                                    '+',   '£000', FALSE, 'NON_PAY_EXCL_EBITDA'),
    ('EXP0260',  'TAC08 Op Exp',   'Impairments net of reversals',                   '+/-', '£000', FALSE, 'NON_PAY_EXCL_EBITDA'),
    ('EXP0290A', 'TAC08 Op Exp',   'Clinical negligence premium (NHS Resolution)',    '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0300',  'TAC08 Op Exp',   'Research and development - staff costs',          '+',   '£000', FALSE, 'PAY'),
    ('EXP0320',  'TAC08 Op Exp',   'Education and training - staff costs',            '+',   '£000', FALSE, 'PAY'),
    ('EXP0350',  'TAC08 Op Exp',   'Redundancy costs - staff',                        '+',   '£000', FALSE, 'PAY'),
    ('EXP0370',  'TAC08 Op Exp',   'PFI / LIFT charges (on-SoFP)',                   '+',   '£000', FALSE, 'NON_PAY'),
    ('EXP0390',  'TAC08 Op Exp',   'Total operating expenditure',                     '+',   '£000', TRUE,  'TOTAL_EXPENDITURE'),
    -- Staff costs (pay breakdown)
    ('STA0220',  'TAC09 Staff',    'Total gross staff costs',                         '+',   '£000', TRUE,  'PAY'),
    ('STA0250',  'TAC09 Staff',    'Total staff costs (net of recoveries)',           '+',   '£000', TRUE,  'PAY'),
    -- WTE numbers
    ('STA0310',  'TAC09 Staff',    'Medical and dental WTE',                          '+',   'No.',  FALSE, 'STAFF_WTE'),
    ('STA0330',  'TAC09 Staff',    'Administration and estates WTE',                  '+',   'No.',  FALSE, 'STAFF_WTE'),
    ('STA0340',  'TAC09 Staff',    'Healthcare assistants WTE',                       '+',   'No.',  FALSE, 'STAFF_WTE'),
    ('STA0350',  'TAC09 Staff',    'Nursing, midwifery and health visiting WTE',      '+',   'No.',  FALSE, 'STAFF_WTE'),
    ('STA0370',  'TAC09 Staff',    'Scientific, therapeutic and technical WTE',       '+',   'No.',  FALSE, 'STAFF_WTE'),
    ('STA0410',  'TAC09 Staff',    'Total average WTE',                               '+',   'No.',  TRUE,  'STAFF_WTE'),
    -- Staff sickness
    ('STA0530',  'TAC09 Staff',    'Total days lost to sickness',                     '+',   'No.',  FALSE, 'STAFF_WTE'),
    ('STA0550',  'TAC09 Staff',    'Average working days lost per WTE',               '+',   'No.',  FALSE, 'STAFF_WTE');


-- ============================================================
-- FACT TABLE
-- ============================================================

-- fct_tac: normalised fact table — one row per provider x year x subcode
DROP TABLE IF EXISTS nhs_silver.fct_tac CASCADE;
CREATE TABLE nhs_silver.fct_tac (
    tac_id              BIGSERIAL       PRIMARY KEY,
    org_code            CHAR(3)         NOT NULL REFERENCES nhs_silver.dim_trust(org_code),
    financial_year      CHAR(7)         NOT NULL REFERENCES nhs_silver.dim_financial_year(financial_year),
    worksheet_name      VARCHAR(50)     NOT NULL REFERENCES nhs_silver.dim_worksheet(worksheet_name),
    table_id            SMALLINT        NOT NULL,
    main_code           VARCHAR(20)     NOT NULL,
    sub_code            VARCHAR(20)     NOT NULL,
    total_000s          NUMERIC(14, 0)  NOT NULL,  -- £000s (or WTE No. for staff rows)
    trust_type          VARCHAR(20)     NOT NULL,  -- NHS_TRUST | FOUNDATION_TRUST
    source_file         VARCHAR(200)    NOT NULL,
    load_ts             TIMESTAMPTZ     DEFAULT now(),
    UNIQUE (org_code, financial_year, main_code, sub_code)
);

CREATE INDEX idx_fct_tac_org_year    ON nhs_silver.fct_tac (org_code, financial_year);
CREATE INDEX idx_fct_tac_sub_code    ON nhs_silver.fct_tac (sub_code);
CREATE INDEX idx_fct_tac_worksheet   ON nhs_silver.fct_tac (worksheet_name);
CREATE INDEX idx_fct_tac_year        ON nhs_silver.fct_tac (financial_year);


-- ============================================================
-- ANALYTICAL VIEWS
-- ============================================================

-- v_income_expenditure: top-level I&E summary from TAC02 SoCI (CY rows only)
CREATE OR REPLACE VIEW nhs_gold.v_income_expenditure AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,
    MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END) AS patient_care_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END) AS other_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END)
        + COALESCE(MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END), 0)
        AS total_income_000s,
    ABS(MAX(CASE WHEN f.sub_code = 'SCI0125A' THEN f.total_000s END)) AS total_expenditure_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s END) AS operating_surplus_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240'  THEN f.total_000s END) AS net_surplus_000s
FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC02 SoCI'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;


-- v_expenditure_breakdown: operating expenditure by category
CREATE OR REPLACE VIEW nhs_gold.v_expenditure_breakdown AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,
    SUM(CASE WHEN sc.analytics_category = 'PAY'              THEN f.total_000s ELSE 0 END) AS pay_000s,
    SUM(CASE WHEN sc.analytics_category = 'NON_PAY'          THEN f.total_000s ELSE 0 END) AS non_pay_000s,
    SUM(CASE WHEN sc.analytics_category = 'NON_PAY_EXCL_EBITDA' THEN f.total_000s ELSE 0 END) AS depreciation_amort_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0170' THEN f.total_000s END) AS drugs_cost_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0130' THEN f.total_000s END) AS staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0390' THEN f.total_000s END) AS total_expenditure_000s
FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t  ON f.org_code = t.org_code
JOIN nhs_silver.dim_subcode sc ON f.sub_code = sc.sub_code
WHERE f.worksheet_name = 'TAC08 Op Exp'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;


-- v_workforce: staff costs and WTE from TAC09
CREATE OR REPLACE VIEW nhs_gold.v_workforce AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,
    MAX(CASE WHEN f.sub_code = 'STA0250'  THEN f.total_000s END) AS total_staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'STA0220'  THEN f.total_000s END) AS gross_staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'STA0410'  THEN f.total_000s END) AS total_wte,
    MAX(CASE WHEN f.sub_code = 'STA0310'  THEN f.total_000s END) AS medical_wte,
    MAX(CASE WHEN f.sub_code = 'STA0350'  THEN f.total_000s END) AS nursing_wte,
    MAX(CASE WHEN f.sub_code = 'STA0330'  THEN f.total_000s END) AS admin_estates_wte,
    MAX(CASE WHEN f.sub_code = 'STA0370'  THEN f.total_000s END) AS scientific_tech_wte,
    MAX(CASE WHEN f.sub_code = 'STA0550'  THEN f.total_000s END) AS avg_days_lost_per_wte
FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC09 Staff'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;


-- v_kpis: computed KPIs joining income, expenditure and workforce
CREATE OR REPLACE VIEW nhs_gold.v_kpis AS
WITH ie AS (SELECT * FROM nhs_gold.v_income_expenditure),
     exp AS (SELECT * FROM nhs_gold.v_expenditure_breakdown),
     wf  AS (SELECT * FROM nhs_gold.v_workforce)
SELECT
    ie.org_code,
    ie.organisation_name,
    ie.sector,
    ie.region,
    ie.trust_type,
    ie.financial_year,
    ie.total_income_000s,
    ie.total_expenditure_000s,
    ie.operating_surplus_000s,
    ie.net_surplus_000s,
    exp.pay_000s,
    exp.staff_cost_000s,
    exp.drugs_cost_000s,
    exp.depreciation_amort_000s,
    wf.total_wte,
    wf.medical_wte,
    wf.nursing_wte,
    wf.avg_days_lost_per_wte,
    -- EBITDA = Operating surplus + Depreciation + Amortisation + Impairments
    ie.operating_surplus_000s + COALESCE(exp.depreciation_amort_000s, 0) AS ebitda_000s,
    -- EBITDA Margin %
    ROUND(
        (ie.operating_surplus_000s + COALESCE(exp.depreciation_amort_000s, 0))::NUMERIC
        / NULLIF(ie.total_income_000s, 0) * 100, 1
    ) AS ebitda_margin_pct,
    -- Pay as % of income
    ROUND(exp.pay_000s::NUMERIC / NULLIF(ie.total_income_000s, 0) * 100, 1) AS pay_pct_income,
    -- Cost per WTE (£000s per WTE)
    ROUND(exp.staff_cost_000s::NUMERIC / NULLIF(wf.total_wte, 0), 1) AS cost_per_wte_000s,
    -- Surplus margin %
    ROUND(ie.net_surplus_000s::NUMERIC / NULLIF(ie.total_income_000s, 0) * 100, 1) AS net_surplus_margin_pct
FROM ie
LEFT JOIN exp ON ie.org_code = exp.org_code AND ie.financial_year = exp.financial_year
LEFT JOIN wf  ON ie.org_code = wf.org_code  AND ie.financial_year = wf.financial_year;
