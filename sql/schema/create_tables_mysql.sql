-- NHS Trust Financial Analytics — MySQL Schema
-- Databases: nhs_bronze (raw landing) -> nhs_silver (conformed dims/fact) -> nhs_gold (analytical views)
-- All monetary values in £000s unless stated otherwise
-- Source: NHS England TAC (Trust Accounts Consolidation) publications

-- ============================================================
-- DATABASES
-- ============================================================

CREATE DATABASE IF NOT EXISTS nhs_bronze
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS nhs_silver
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS nhs_gold
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;


-- ============================================================
-- BRONZE — STAGING TABLES (raw, near-verbatim landing)
-- ============================================================

USE nhs_bronze;

DROP TABLE IF EXISTS stg_tac_raw;
CREATE TABLE stg_tac_raw (
    id                  BIGINT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organisation_name   VARCHAR(300)    NOT NULL,
    worksheet_name      VARCHAR(50)     NOT NULL,
    table_id            SMALLINT        NOT NULL,
    main_code           VARCHAR(20)     NOT NULL,
    row_num             SMALLINT        NOT NULL,
    sub_code            VARCHAR(20)     NOT NULL,
    total               DECIMAL(14,0)   NOT NULL,        -- £000s
    source_file         VARCHAR(200)    NOT NULL,
    trust_type          VARCHAR(20)     NOT NULL,        -- NHS_TRUST | FOUNDATION_TRUST
    financial_year      CHAR(7)         NOT NULL,        -- e.g. 2023/24
    year_type           CHAR(2)         NOT NULL,        -- CY | PY
    load_ts             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_stg_org_year  (organisation_name(100), financial_year),
    INDEX idx_stg_sub_code  (sub_code),
    INDEX idx_stg_year_type (financial_year, year_type)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS stg_provider_list;
CREATE TABLE stg_provider_list (
    id                  INT             NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organisation_name   VARCHAR(300)    NOT NULL,
    org_code            CHAR(3)         NOT NULL,
    region              VARCHAR(100),
    sector              VARCHAR(50),
    comments            TEXT,
    source_file         VARCHAR(200)    NOT NULL,
    trust_type          VARCHAR(20)     NOT NULL,        -- NHS_TRUST | FOUNDATION_TRUST
    financial_year      CHAR(7)         NOT NULL,
    load_ts             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_prov_org_code (org_code),
    INDEX idx_prov_name     (organisation_name(100))
) ENGINE=InnoDB;


-- ============================================================
-- SILVER — CONFORMED DIMENSIONS
-- ============================================================

USE nhs_silver;

-- Drop fct_tac and dim_subcode first, even though neither is (re)created until later in this
-- file -- fct_tac FK-references dim_trust/dim_financial_year/dim_worksheet, and dim_subcode
-- FK-references dim_worksheet, so on a rerun those tables' DROPs would otherwise fail with
-- "referenced by a foreign key constraint".
DROP TABLE IF EXISTS fct_tac;
DROP TABLE IF EXISTS dim_subcode;

DROP TABLE IF EXISTS dim_trust;
CREATE TABLE dim_trust (
    org_code            CHAR(3)         NOT NULL PRIMARY KEY,
    organisation_name   VARCHAR(300)    NOT NULL,
    trust_type          VARCHAR(20)     NOT NULL,        -- NHS_TRUST | FOUNDATION_TRUST
    sector              VARCHAR(50),                     -- Acute | Mental Health | Community | Ambulance
    region              VARCHAR(100),
    is_foundation       TINYINT(1)      NOT NULL DEFAULT 0,
    first_year_seen     CHAR(7),
    last_year_seen      CHAR(7),
    updated_ts          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

DROP TABLE IF EXISTS dim_financial_year;
CREATE TABLE dim_financial_year (
    financial_year      CHAR(7)         NOT NULL PRIMARY KEY,  -- e.g. 2023/24
    start_date          DATE            NOT NULL,              -- 1 April
    end_date            DATE            NOT NULL,              -- 31 March
    year_label_short    CHAR(5)         NOT NULL,              -- e.g. 23/24
    is_complete         TINYINT(1)      NOT NULL DEFAULT 1
) ENGINE=InnoDB;

INSERT INTO dim_financial_year VALUES
    ('2019/20', '2019-04-01', '2020-03-31', '19/20', 1),
    ('2020/21', '2020-04-01', '2021-03-31', '20/21', 1),
    ('2021/22', '2021-04-01', '2022-03-31', '21/22', 1),
    ('2022/23', '2022-04-01', '2023-03-31', '22/23', 1),
    ('2023/24', '2023-04-01', '2024-03-31', '23/24', 1);

DROP TABLE IF EXISTS dim_worksheet;
CREATE TABLE dim_worksheet (
    worksheet_name      VARCHAR(50)     NOT NULL PRIMARY KEY,
    schedule_title      VARCHAR(200)    NOT NULL,
    category             VARCHAR(50)     NOT NULL,
    sub_code_prefix      VARCHAR(10)
) ENGINE=InnoDB;

-- All 28 real TAC worksheets (confirmed present in the raw "All data" sheet of every source
-- file). sub_code_prefix is informational only (dim_subcode.worksheet_name is the real FK) --
-- TAC03 SoFP's prefix is corrected to 'BAL' here (was wrongly seeded as 'SFP'; the real
-- SubCodes for that schedule are BAL1100-BAL1500, confirmed against both the raw files and
-- NHS England's illustrative TAC workbook).
INSERT INTO dim_worksheet VALUES
    ('TAC02 SoCI',              'Statement of Comprehensive Income',          'SUMMARY',        'SCI'),
    ('TAC03 SoFP',               'Statement of Financial Position',            'BALANCE_SHEET',  'BAL'),
    ('TAC04 SOCIE',              'Statement of Changes in Equity',             'EQUITY',         'SCE'),
    ('TAC05 SoCF',                'Statement of Cash Flows',                    'CASH_FLOW',      'SCF'),
    ('TAC06 Op Inc 1',           'Operating Income from Patient Care',         'INCOME',         'INC0'),
    ('TAC07 Op Inc 2',           'Other Operating Income',                     'INCOME',         'INC1'),
    ('TAC08 Op Exp',              'Operating Expenditure',                      'EXPENDITURE',    'EXP'),
    ('TAC09 Staff',               'Staff Costs and WTE Numbers',                'STAFF',          'STA'),
    ('TAC11 Finance & other',    'Finance Income, Expense and PDC',            'FINANCE',        'FIN'),
    ('TAC12 Impairment',         'Asset Impairments',                          'OTHER',          'IMP'),
    ('TAC13 Intangibles',        'Intangible Assets',                          'BALANCE_SHEET',  'INT'),
    ('TAC14 PPE',                 'Property Plant and Equipment',               'BALANCE_SHEET',  'PPE'),
    ('TAC14A RoU Assets',        'Right-of-Use Assets (IFRS 16)',              'BALANCE_SHEET',  'ROU'),
    ('TAC14X RoU Assets PY',     'Right-of-Use Assets (IFRS 16) — Prior Year', 'BALANCE_SHEET',  'ROU'),
    ('TAC15 Investments & groups','Investments in Joint Ventures and Associates','BALANCE_SHEET','IGR'),
    ('TAC16 AHFS',                'Assets Held for Sale and Disposal Groups',   'BALANCE_SHEET',  'AHF'),
    ('TAC17 Inventories',        'Inventories',                                'BALANCE_SHEET',  'INV'),
    ('TAC18 Receivables',        'Receivables and Debtors',                    'BALANCE_SHEET',  'REC'),
    ('TAC19 CCE',                 'Cash and Cash Equivalents',                  'BALANCE_SHEET',  'CCE'),
    ('TAC20 Payables',            'Payables and Creditors',                     'BALANCE_SHEET',  'PAY'),
    ('TAC21 Borrowings',         'Borrowings',                                 'BALANCE_SHEET',  'BOR'),
    ('TAC22 Provisions',         'Provisions for Liabilities',                 'BALANCE_SHEET',  'PRV'),
    ('TAC24 On-SoFP PFI',        'On-SoFP PFI and Other Service Concessions',  'BALANCE_SHEET',  'PFI'),
    ('TAC25 Off-SoFP PFI',       'Off-SoFP PFI Residual Interests',            'OTHER',          'PFI'),
    ('TAC26 Pension',             'Pension Liabilities',                        'BALANCE_SHEET',  'PEN'),
    ('TAC27 Fin Inst',           'Financial Instruments',                      'OTHER',          'FI'),
    ('TAC28 Disclosures',        'Statutory Disclosures (NHS Trusts only)',    'OTHER',          'DIS'),
    ('TAC29 Losses+SP',          'Losses and Special Payments',                'OTHER',          'LSP');

DROP TABLE IF EXISTS dim_subcode;
CREATE TABLE dim_subcode (
    sub_code            VARCHAR(20)     NOT NULL PRIMARY KEY,
    worksheet_name      VARCHAR(50)     NOT NULL,
    description         VARCHAR(300)    NOT NULL,
    expected_sign       CHAR(3),
    unit                VARCHAR(10)     NOT NULL DEFAULT '£000',
    is_subtotal         TINYINT(1)      NOT NULL DEFAULT 0,
    analytics_category  VARCHAR(30),
    FOREIGN KEY (worksheet_name) REFERENCES dim_worksheet(worksheet_name)
) ENGINE=InnoDB;

-- Hand-curated labels for the 5 worksheets used by the analytical views below
-- (v_income_expenditure, v_expenditure_breakdown, v_workforce, v_kpis) — analytics_category
-- here drives v_expenditure_breakdown's PAY / NON_PAY / NON_PAY_EXCL_EBITDA grouping.
INSERT INTO dim_subcode VALUES
    -- SoCI summary
    ('SCI0100A', 'TAC02 SoCI', 'Operating income from patient care activities',         '+',   '£000', 1, 'PATIENT_INCOME'),
    ('SCI0110A', 'TAC02 SoCI', 'Other operating income',                                '+',   '£000', 1, 'OTHER_INCOME'),
    ('SCI0125A', 'TAC02 SoCI', 'Operating expenses (total)',                            '-',   '£000', 1, 'TOTAL_EXPENDITURE'),
    ('SCI0140A', 'TAC02 SoCI', 'Operating surplus / (deficit)',                         '+/-', '£000', 1, 'OPERATING_SURPLUS'),
    ('SCI0150',  'TAC02 SoCI', 'Finance income',                                        '+',   '£000', 0, NULL),
    ('SCI0160',  'TAC02 SoCI', 'Finance expense',                                       '-',   '£000', 0, NULL),
    ('SCI0170',  'TAC02 SoCI', 'PDC dividend expense',                                  '-',   '£000', 0, NULL),
    ('SCI0240',  'TAC02 SoCI', 'Surplus / (deficit) for the year',                     '+/-', '£000', 1, 'NET_SURPLUS'),
    ('SOC0190',  'TAC02 SoCI', 'Total comprehensive income / (expense)',                '+/-', '£000', 1, NULL),
    -- Patient care income by nature
    ('INC0197',  'TAC06 Op Inc 1', 'API income - Variable (acute)',                     '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0198',  'TAC06 Op Inc 1', 'API income - Fixed (acute)',                        '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0200',  'TAC06 Op Inc 1', 'High cost drugs income from commissioners',         '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0210',  'TAC06 Op Inc 1', 'Other NHS clinical income (acute)',                 '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0231',  'TAC06 Op Inc 1', 'API income (mental health)',                        '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0302',  'TAC06 Op Inc 1', 'API income (community)',                            '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0330',  'TAC06 Op Inc 1', 'Private patient income',                            '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0332',  'TAC06 Op Inc 1', 'Pay award central funding',                         '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0340',  'TAC06 Op Inc 1', 'Other clinical income',                             '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC0350',  'TAC06 Op Inc 1', 'Total income from patient care activities',         '+',   '£000', 1, 'PATIENT_INCOME'),
    -- Patient care income by source
    ('INC1100',  'TAC06 Op Inc 1', 'Patient care income from NHS England',              '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC1115',  'TAC06 Op Inc 1', 'Patient care income from Integrated Care Boards',  '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC1140',  'TAC06 Op Inc 1', 'Patient care income from Local Authorities',        '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC1170',  'TAC06 Op Inc 1', 'Non-NHS: private patients',                         '+',   '£000', 0, 'PATIENT_INCOME'),
    ('INC1220',  'TAC06 Op Inc 1', 'Total income from patient care (by source)',        '+',   '£000', 1, 'PATIENT_INCOME'),
    -- Other operating income
    ('INC1230A', 'TAC07 Op Inc 2', 'Research and development income (IFRS 15)',         '+',   '£000', 0, 'OTHER_INCOME'),
    ('INC1240A', 'TAC07 Op Inc 2', 'Education and training income',                     '+',   '£000', 0, 'OTHER_INCOME'),
    ('INC1280A', 'TAC07 Op Inc 2', 'Non-patient care services to other bodies',         '+',   '£000', 0, 'OTHER_INCOME'),
    ('INC1360',  'TAC07 Op Inc 2', 'Total other operating income',                      '+',   '£000', 1, 'OTHER_INCOME'),
    ('INC1365',  'TAC07 Op Inc 2', 'Total operating income',                            '+',   '£000', 1, 'TOTAL_INCOME'),
    -- Operating expenditure
    ('EXP0100',  'TAC08 Op Exp', 'Purchase of healthcare from NHS bodies',              '+',   '£000', 0, 'NON_PAY'),
    ('EXP0110',  'TAC08 Op Exp', 'Purchase of healthcare from non-NHS bodies',          '+',   '£000', 0, 'NON_PAY'),
    ('EXP0130',  'TAC08 Op Exp', 'Staff and executive directors costs',                 '+',   '£000', 0, 'PAY'),
    ('EXP0140',  'TAC08 Op Exp', 'Non-executive directors costs',                       '+',   '£000', 0, 'PAY'),
    ('EXP0150',  'TAC08 Op Exp', 'Supplies and services - clinical',                    '+',   '£000', 0, 'NON_PAY'),
    ('EXP0160',  'TAC08 Op Exp', 'Supplies and services - general',                     '+',   '£000', 0, 'NON_PAY'),
    ('EXP0170',  'TAC08 Op Exp', 'Drugs costs',                                         '+',   '£000', 0, 'NON_PAY'),
    ('EXP0190',  'TAC08 Op Exp', 'Consultancy',                                         '+',   '£000', 0, 'NON_PAY'),
    ('EXP0200',  'TAC08 Op Exp', 'Establishment costs',                                 '+',   '£000', 0, 'NON_PAY'),
    ('EXP0210',  'TAC08 Op Exp', 'Premises - business rates',                           '+',   '£000', 0, 'NON_PAY'),
    ('EXP0220',  'TAC08 Op Exp', 'Premises - other',                                    '+',   '£000', 0, 'NON_PAY'),
    ('EXP0240',  'TAC08 Op Exp', 'Depreciation',                                        '+',   '£000', 0, 'NON_PAY_EXCL_EBITDA'),
    ('EXP0250',  'TAC08 Op Exp', 'Amortisation',                                        '+',   '£000', 0, 'NON_PAY_EXCL_EBITDA'),
    ('EXP0260',  'TAC08 Op Exp', 'Impairments net of reversals',                       '+/-', '£000', 0, 'NON_PAY_EXCL_EBITDA'),
    ('EXP0290A', 'TAC08 Op Exp', 'Clinical negligence premium (NHS Resolution)',        '+',   '£000', 0, 'NON_PAY'),
    ('EXP0300',  'TAC08 Op Exp', 'Research and development - staff costs',              '+',   '£000', 0, 'PAY'),
    ('EXP0320',  'TAC08 Op Exp', 'Education and training - staff costs',                '+',   '£000', 0, 'PAY'),
    ('EXP0350',  'TAC08 Op Exp', 'Redundancy costs - staff',                            '+',   '£000', 0, 'PAY'),
    ('EXP0370',  'TAC08 Op Exp', 'PFI / LIFT charges (on-SoFP)',                       '+',   '£000', 0, 'NON_PAY'),
    ('EXP0390',  'TAC08 Op Exp', 'Total operating expenditure',                         '+',   '£000', 1, 'TOTAL_EXPENDITURE'),
    -- Staff costs
    ('STA0220',  'TAC09 Staff', 'Total gross staff costs',                              '+',   '£000', 1, 'PAY'),
    ('STA0250',  'TAC09 Staff', 'Total staff costs (net of recoveries)',                '+',   '£000', 1, 'PAY'),
    -- WTE numbers
    ('STA0310',  'TAC09 Staff', 'Medical and dental WTE',                               '+',   'No.',  0, 'STAFF_WTE'),
    ('STA0330',  'TAC09 Staff', 'Administration and estates WTE',                       '+',   'No.',  0, 'STAFF_WTE'),
    ('STA0340',  'TAC09 Staff', 'Healthcare assistants WTE',                            '+',   'No.',  0, 'STAFF_WTE'),
    ('STA0350',  'TAC09 Staff', 'Nursing, midwifery and health visiting WTE',           '+',   'No.',  0, 'STAFF_WTE'),
    ('STA0370',  'TAC09 Staff', 'Scientific, therapeutic and technical WTE',            '+',   'No.',  0, 'STAFF_WTE'),
    ('STA0410',  'TAC09 Staff', 'Total average WTE',                                    '+',   'No.',  1, 'STAFF_WTE'),
    ('STA0530',  'TAC09 Staff', 'Total days lost to sickness',                          '+',   'No.',  0, 'STAFF_WTE'),
    ('STA0550',  'TAC09 Staff', 'Average working days lost per WTE',                    '+',   'No.',  0, 'STAFF_WTE');

-- Full label reference for the remaining 22 worksheets (TAC03-05, TAC11-29), generated by
-- python/ingestion/build_subcode_reference.py from NHS England's illustrative TAC workbook.
-- Covers every real SubCode found in the raw source files that isn't hand-curated above.
-- TAC14X RoU Assets PY is excluded here (see script) -- it reuses TAC14A's exact SubCode
-- values as a prior-year comparative, which would collide on this table's PRIMARY KEY.

-- TAC03 SoFP
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('BAL1100', 'TAC03 SoFP', 'Intangible assets', '+', '£000', 0, NULL),
    ('BAL1110', 'TAC03 SoFP', 'Property, plant and equipment', '+', '£000', 0, NULL),
    ('BAL1115', 'TAC03 SoFP', 'Right of use assets', '+', '£000', 0, NULL),
    ('BAL1120', 'TAC03 SoFP', 'Investment property', '+', '£000', 0, NULL),
    ('BAL1130', 'TAC03 SoFP', 'Investments in joint ventures and associates', '+', '£000', 0, NULL),
    ('BAL1140', 'TAC03 SoFP', 'Other investments / financial assets', '+', '£000', 0, NULL),
    ('BAL1150', 'TAC03 SoFP', 'Receivables', '+', '£000', 0, NULL),
    ('BAL1170', 'TAC03 SoFP', 'Other assets', '+', '£000', 0, NULL),
    ('BAL1180', 'TAC03 SoFP', 'Total non-current assets', '+', '£000', 1, NULL),
    ('BAL1190', 'TAC03 SoFP', 'Inventories', '+', '£000', 0, NULL),
    ('BAL1200', 'TAC03 SoFP', 'Receivables', '+', '£000', 0, NULL),
    ('BAL1210', 'TAC03 SoFP', 'Other investments / financial assets', '+', '£000', 0, NULL),
    ('BAL1220', 'TAC03 SoFP', 'Other assets', '+', '£000', 0, NULL),
    ('BAL1230', 'TAC03 SoFP', 'Non-current assets held for sale and assets in disposal groups', '+', '£000', 0, NULL),
    ('BAL1240', 'TAC03 SoFP', 'Cash and cash equivalents', '+', '£000', 0, NULL),
    ('BAL1250', 'TAC03 SoFP', 'Total current assets', '+', '£000', 1, NULL),
    ('BAL1260', 'TAC03 SoFP', 'Trade and other payables', '-', '£000', 0, NULL),
    ('BAL1270', 'TAC03 SoFP', 'Borrowings', '-', '£000', 0, NULL),
    ('BAL1280', 'TAC03 SoFP', 'Other financial liabilities', '-', '£000', 0, NULL),
    ('BAL1290', 'TAC03 SoFP', 'Provisions', '-', '£000', 0, NULL),
    ('BAL1300', 'TAC03 SoFP', 'Other liabilities', '-', '£000', 0, NULL),
    ('BAL1310', 'TAC03 SoFP', 'Liabilities in disposal groups', '-', '£000', 0, NULL),
    ('BAL1320', 'TAC03 SoFP', 'Total current liabilities', '-', '£000', 1, NULL),
    ('BAL1330', 'TAC03 SoFP', 'Total assets less current liabilities', '+/-', '£000', 1, NULL),
    ('BAL1340', 'TAC03 SoFP', 'Trade and other payables', '-', '£000', 0, NULL),
    ('BAL1350', 'TAC03 SoFP', 'Borrowings', '-', '£000', 0, NULL),
    ('BAL1360', 'TAC03 SoFP', 'Other financial liabilities', '-', '£000', 0, NULL),
    ('BAL1370', 'TAC03 SoFP', 'Provisions', '-', '£000', 0, NULL),
    ('BAL1380', 'TAC03 SoFP', 'Other liabilities', '-', '£000', 0, NULL),
    ('BAL1390', 'TAC03 SoFP', 'Total non-current liabilities', '-', '£000', 1, NULL),
    ('BAL1400', 'TAC03 SoFP', 'Total assets employed', '+/-', '£000', 1, NULL),
    ('BAL1410', 'TAC03 SoFP', 'Public dividend capital', '+', '£000', 0, NULL),
    ('BAL1420', 'TAC03 SoFP', 'Revaluation reserve', '+', '£000', 0, NULL),
    ('BAL1430', 'TAC03 SoFP', 'Financial assets at FV through OCI reserve', '+/-', '£000', 0, NULL),
    ('BAL1440', 'TAC03 SoFP', 'Other reserves', '+/-', '£000', 0, NULL),
    ('BAL1450', 'TAC03 SoFP', 'Merger reserve', '+/-', '£000', 0, NULL),
    ('BAL1460', 'TAC03 SoFP', 'Income and expenditure reserve', '+/-', '£000', 0, NULL),
    ('BAL1470', 'TAC03 SoFP', 'Non-controlling Interest', '+', '£000', 0, NULL),
    ('BAL1490', 'TAC03 SoFP', 'Charitable fund reserves', '+', '£000', 0, NULL),
    ('BAL1500', 'TAC03 SoFP', 'Total taxpayers'' and others'' equity', '+/-', '£000', 1, NULL);

-- TAC04 SOCIE
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('SCE0010', 'TAC04 SOCIE', 'Taxpayers'' and others'' equity at 1 April 2023 - brought forward', '+/-', '£000', 0, NULL),
    ('SCE0031', 'TAC04 SOCIE', 'Application of IFRS 16 measurement principles to PFI liability on 1 April 2024', '+/-', '£000', 0, NULL),
    ('SCE0040', 'TAC04 SOCIE', 'At start of period for new FTs', '+/-', '£000', 0, NULL),
    ('SCE0050', 'TAC04 SOCIE', 'Surplus/(deficit) for the year', '+/-', '£000', 0, NULL),
    ('SCE0060', 'TAC04 SOCIE', 'Transfers by absorption: transfers between reserves', NULL, '£000', 0, NULL),
    ('SCE0065', 'TAC04 SOCIE', 'Transfers by absorption: transfers between reserves (charitable fund)', NULL, '£000', 0, NULL),
    ('SCE0070', 'TAC04 SOCIE', 'Transfer from reval reserve to I&E reserve for impairments arising from consumption of economic benefits', NULL, '£000', 0, NULL),
    ('SCE0080', 'TAC04 SOCIE', 'Transfers between reserves', NULL, '£000', 0, NULL),
    ('SCE0090', 'TAC04 SOCIE', 'Net impairments', '+/-', '£000', 0, NULL),
    ('SCE0100', 'TAC04 SOCIE', 'Revaluations - property, plant and equipment', '+', '£000', 0, NULL),
    ('SCE0110', 'TAC04 SOCIE', 'Revaluations - intangible assets', '+', '£000', 0, NULL),
    ('SCE0112', 'TAC04 SOCIE', 'Revaluations - right of use assets', '+', '£000', 0, NULL),
    ('SCE0115', 'TAC04 SOCIE', 'Revaluations and impairments - charitable fund assets', '+/-', '£000', 0, NULL),
    ('SCE0120', 'TAC04 SOCIE', 'Transfer to retained earnings on disposal of assets', NULL, '£000', 0, NULL),
    ('SCE0130', 'TAC04 SOCIE', 'Share of comprehensive income from associates and joint ventures', '+/-', '£000', 0, NULL),
    ('SCE0140', 'TAC04 SOCIE', 'Fair value gains/(losses) on financial assets mandated at FV through OCI', '+/-', '£000', 0, NULL),
    ('SCE0145', 'TAC04 SOCIE', 'Fair value gains/(losses) on equity instruments designated at FV through OCI', '+/-', '£000', 0, NULL),
    ('SCE0150', 'TAC04 SOCIE', 'Recycling gains/(losses) on disposal of financial assets mandated at FV through OCI', '+/-', '£000', 0, NULL),
    ('SCE0160', 'TAC04 SOCIE', 'Foreign exchange gains/(losses) recognised directly in OCI', '+/-', '£000', 0, NULL),
    ('SCE0170', 'TAC04 SOCIE', 'Other recognised gains and losses', '+/-', '£000', 0, NULL),
    ('SCE0180', 'TAC04 SOCIE', 'Remeasurements of defined net benefit pension scheme liability / asset', '+/-', '£000', 0, NULL),
    ('SCE0200', 'TAC04 SOCIE', 'Public dividend capital received', '+', '£000', 0, NULL),
    ('SCE0210', 'TAC04 SOCIE', 'Public dividend capital repaid', '-', '£000', 0, NULL),
    ('SCE0220', 'TAC04 SOCIE', 'Public dividend capital written off', NULL, '£000', 0, NULL),
    ('SCE0230', 'TAC04 SOCIE', 'Other movements in PDC in year (unlocked on request)', '+/-', '£000', 0, NULL),
    ('SCE0240', 'TAC04 SOCIE', 'Reserves eliminated on dissolution (unlocked on request)', '+/-', '£000', 0, NULL),
    ('SCE0250', 'TAC04 SOCIE', 'Other reserve movements', '+/-', '£000', 0, NULL),
    ('SCE0255', 'TAC04 SOCIE', 'Other reserve movements - charitable fund consolidation adjustment', '+/-', '£000', 0, NULL),
    ('SCE0260', 'TAC04 SOCIE', 'Transfer to FT upon authorisation', '+/-', '£000', 0, NULL),
    ('SCE0270', 'TAC04 SOCIE', 'Taxpayers'' and others'' equity at 31 March 2024', '+/-', '£000', 0, NULL),
    ('SCE0020', 'TAC04 SOCIE', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('SCE0030', 'TAC04 SOCIE', 'Taxpayers'' and others'' equity at 1 April 2022 - restated', '+/-', '£000', 0, NULL),
    ('SCE0032', 'TAC04 SOCIE', 'Implementation of IFRS 16 on 1 April 2022', '+/-', '£000', 0, NULL),
    ('SCE0055', 'TAC04 SOCIE', 'Gain / (loss) on transfers by absorption (modified)', '+/-', '£000', 0, NULL);

-- TAC05 SoCF
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('SCF0100A', 'TAC05 SoCF', 'Operating surplus/(deficit) from continuing operations', '+/-', '£000', 0, NULL),
    ('SCF0100B', 'TAC05 SoCF', 'Operating surplus/(deficit) of discontinued operations', '+/-', '£000', 0, NULL),
    ('SCF0100', 'TAC05 SoCF', 'Operating surplus/(deficit)', '+/-', '£000', 0, NULL),
    ('SCF0105', 'TAC05 SoCF', 'Depreciation and amortisation', '+', '£000', 0, NULL),
    ('SCF0110', 'TAC05 SoCF', 'Impairments and reversals', '+', '£000', 0, NULL),
    ('SCF0120', 'TAC05 SoCF', 'Income recognised in respect of capital donations (cash and non-cash)', '-', '£000', 0, NULL),
    ('SCF0125', 'TAC05 SoCF', 'Amortisation of PFI deferred income / credit', '-', '£000', 0, NULL),
    ('SCF0130', 'TAC05 SoCF', 'On SoFP pension liability - employer contributions paid less net charge to the SOCI', '+/-', '£000', 0, NULL),
    ('SCF0135', 'TAC05 SoCF', '(Increase)/decrease in receivables', '+/-', '£000', 0, NULL),
    ('SCF0140A', 'TAC05 SoCF', '(Increase)/decrease in other assets', '+/-', '£000', 0, NULL),
    ('SCF0150', 'TAC05 SoCF', '(Increase)/decrease in inventories', '+/-', '£000', 0, NULL),
    ('SCF0155', 'TAC05 SoCF', 'Increase/(decrease) in trade and other payables', '+/-', '£000', 0, NULL),
    ('SCF0160', 'TAC05 SoCF', 'Increase/(decrease) in other liabilities', '+/-', '£000', 0, NULL),
    ('SCF0165', 'TAC05 SoCF', 'Increase/(decrease) in provisions', '+/-', '£000', 0, NULL),
    ('CFS0010', 'TAC05 SoCF', 'Movements in charitable fund working capital', '+/-', '£000', 0, NULL),
    ('SCF0170', 'TAC05 SoCF', 'Corporation tax (paid) / received', '+/-', '£000', 0, NULL),
    ('SCF0175A', 'TAC05 SoCF', 'Movements in operating cash flows of discontinued operations', '+/-', '£000', 0, NULL),
    ('CFS0020', 'TAC05 SoCF', 'NHS charitable funds: other movements in operating cash flows', '+/-', '£000', 0, NULL),
    ('SCF0175B', 'TAC05 SoCF', 'Other movements in operating cash flows', '+/-', '£000', 0, NULL),
    ('SCF0180', 'TAC05 SoCF', 'Net cash generated from / (used in) operations', '+/-', '£000', 0, NULL),
    ('SCF0185', 'TAC05 SoCF', 'Interest received', '+', '£000', 0, NULL),
    ('SCF0190', 'TAC05 SoCF', 'Purchase of financial assets / investments', '-', '£000', 0, NULL),
    ('SCF0195', 'TAC05 SoCF', 'Proceeds from sales / settlements of financial assets / investments', '+', '£000', 0, NULL),
    ('SCF0200', 'TAC05 SoCF', 'Purchase of intangible assets', '-', '£000', 0, NULL),
    ('SCF0205', 'TAC05 SoCF', 'Proceeds from sales of intangible assets', '+', '£000', 0, NULL),
    ('SCF0210', 'TAC05 SoCF', 'Purchase of property, plant and equipment and investment property', '-', '£000', 0, NULL),
    ('SCF0215', 'TAC05 SoCF', 'Proceeds from sales of property, plant and equipment and investment property', '+', '£000', 0, NULL),
    ('SCF0216A', 'TAC05 SoCF', 'Initial direct costs or up front payments in respect of new right of use assets (lessee)', '-', '£000', 0, NULL),
    ('SCF0216B', 'TAC05 SoCF', 'Receipt of cash lease incentives (lessee)', '+', '£000', 0, NULL),
    ('SCF0216C', 'TAC05 SoCF', 'Lease termination fees paid (lessee)', '-', '£000', 0, NULL),
    ('SCF0220', 'TAC05 SoCF', 'Receipt of cash donations to purchase capital assets', '+', '£000', 0, NULL),
    ('SCF0226', 'TAC05 SoCF', 'Prepayment of PFI capital contributions (cash payments)', '-', '£000', 0, NULL),
    ('SCF0227', 'TAC05 SoCF', 'Finance lease receipts (principal and interest)', '+', '£000', 0, NULL),
    ('CFS0030', 'TAC05 SoCF', 'NHS charitable funds: net cash flows from investing activities', '+/-', '£000', 0, NULL),
    ('SCF0235A', 'TAC05 SoCF', 'Cash flows attributable to investing activities of discontinued operations', '+/-', '£000', 0, NULL),
    ('SCF0230', 'TAC05 SoCF', 'Cash movement from acquisitions of business units and subsidiaries (not absorption transfers)', '+/-', '£000', 0, NULL),
    ('SCF0235', 'TAC05 SoCF', 'Cash movement from disposals of business units and subsidiaries (not absorption transfers)', '+/-', '£000', 0, NULL),
    ('SCF0240', 'TAC05 SoCF', 'Net cash generated from/(used in) investing activities', '+/-', '£000', 0, NULL),
    ('SCF0245', 'TAC05 SoCF', 'Public dividend capital received', '+', '£000', 0, NULL),
    ('SCF0250', 'TAC05 SoCF', 'Public dividend capital repaid', '-', '£000', 0, NULL),
    ('CFS1000', 'TAC05 SoCF', 'Movement in loans from the Department of Health and Social Care', '+/-', '£000', 0, NULL),
    ('CFS1010', 'TAC05 SoCF', 'Movement in other loans', '+/-', '£000', 0, NULL),
    ('SCF0275', 'TAC05 SoCF', 'Other capital receipts', '+', '£000', 0, NULL),
    ('SCF0280', 'TAC05 SoCF', 'Capital element of lease liability repayments', '-', '£000', 0, NULL),
    ('SCF0285', 'TAC05 SoCF', 'Capital element of PFI, LIFT and other service concession payments', '-', '£000', 0, NULL),
    ('SCF0290A', 'TAC05 SoCF', 'Interest on DHSC loans', '-', '£000', 0, NULL),
    ('SCF0290C', 'TAC05 SoCF', 'Interest on other loans', '-', '£000', 0, NULL),
    ('SCF0290B', 'TAC05 SoCF', 'Other interest (e.g. overdrafts)', '-', '£000', 0, NULL),
    ('SCF0295', 'TAC05 SoCF', 'Interest element of lease liability repayments', '-', '£000', 0, NULL),
    ('SCF0300', 'TAC05 SoCF', 'Interest element of PFI, LIFT and other service concession obligations', '-', '£000', 0, NULL),
    ('SCF0305', 'TAC05 SoCF', 'PDC dividend (paid)/refunded', '+/-', '£000', 0, NULL),
    ('SCF0310A', 'TAC05 SoCF', 'Cash flows attributable to financing activities of discontinued operations', '+/-', '£000', 0, NULL),
    ('CFS0040', 'TAC05 SoCF', 'NHS charitable funds: net cash flows from financing activities', '+/-', '£000', 0, NULL),
    ('SCF0310', 'TAC05 SoCF', 'Cash flows from (used in) other financing activities', '+/-', '£000', 0, NULL),
    ('SCF0315', 'TAC05 SoCF', 'Net cash generated from/(used in) financing activities', '+/-', '£000', 0, NULL),
    ('SCF0320', 'TAC05 SoCF', 'Increase/(decrease) in cash and cash equivalents', '+/-', '£000', 0, NULL),
    ('SCF0325A', 'TAC05 SoCF', 'Cash and cash equivalents at 1 April - brought forward', '+/-', '£000', 0, NULL),
    ('SCF0325B', 'TAC05 SoCF', 'Prior period adjustments', '+/-', '£000', 0, NULL),
    ('SCF0325', 'TAC05 SoCF', 'Cash and cash equivalents at 1 April - restated', '+/-', '£000', 0, NULL),
    ('SCF0345', 'TAC05 SoCF', 'Cash and cash equivalents at start of period for new FTs', '+/-', '£000', 0, NULL),
    ('SCF0350', 'TAC05 SoCF', 'Cash and cash equivalents transferred by absorption', '+/-', '£000', 0, NULL),
    ('SCF0115', 'TAC05 SoCF', 'Unrealised gains/(losses) on foreign exchange', '+/-', '£000', 0, NULL),
    ('SCF0340', 'TAC05 SoCF', 'Cash transferred to NHS foundation trust upon authorisation as FT', '+/-', '£000', 0, NULL),
    ('SCF0355', 'TAC05 SoCF', 'Cash and cash equivalents at 31 March', '+/-', '£000', 0, NULL);

-- TAC11 Finance & other
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('FIN0010', 'TAC11 Finance & other', 'Interest on bank accounts', '+', '£000', 0, NULL),
    ('FIN0030', 'TAC11 Finance & other', 'Interest income on finance leases', '+', '£000', 0, NULL),
    ('FIN0040', 'TAC11 Finance & other', 'Interest on other investments / financial assets', '+', '£000', 0, NULL),
    ('FIN0050', 'TAC11 Finance & other', 'NHS charitable fund investment income', '+', '£000', 0, NULL),
    ('FIN0060', 'TAC11 Finance & other', 'Other', '+', '£000', 0, NULL),
    ('FIN0070', 'TAC11 Finance & other', 'Total finance revenue', '+', '£000', 1, NULL),
    ('SCI1210', 'TAC11 Finance & other', '- Capital loans', '+', '£000', 0, NULL),
    ('SCI1220', 'TAC11 Finance & other', '- Revenue support / working capital loans', '+', '£000', 0, NULL),
    ('SCI1240', 'TAC11 Finance & other', 'Interest on other loans', '+', '£000', 0, NULL),
    ('SCI1250', 'TAC11 Finance & other', 'Interest on bank overdrafts', '+', '£000', 0, NULL),
    ('SCI1260', 'TAC11 Finance & other', 'Interest on lease obligations', '+', '£000', 0, NULL),
    ('SCI1270', 'TAC11 Finance & other', 'Interest on the late payment of commercial debt', '+', '£000', 0, NULL),
    ('SCI1280', 'TAC11 Finance & other', '- Main finance costs', '+', '£000', 0, NULL),
    ('SCI1290', 'TAC11 Finance & other', '- Contingent finance costs', '+', '£000', 0, NULL),
    ('SCI1295', 'TAC11 Finance & other', '- Remeasurement of PFI / other service concession liability resulting from change in index or rate', '+/-', '£000', 0, NULL),
    ('FIN0080', 'TAC11 Finance & other', 'Total interest expense', '+', '£000', 1, NULL),
    ('SCI1320', 'TAC11 Finance & other', 'Unwinding of discount on provisions', '+/-', '£000', 0, NULL),
    ('SCI1330', 'TAC11 Finance & other', 'Other finance costs', '+', '£000', 0, NULL),
    ('SCI1340', 'TAC11 Finance & other', 'Total finance expenditure', '+', '£000', 1, NULL),
    ('FIN0089', 'TAC11 Finance & other', 'Total liability accruing in year under this legislation as a result of late payments', '+', '£000', 1, NULL),
    ('FIN0090', 'TAC11 Finance & other', 'Amounts actually paid and included within other interest arising from claims made under this legislation', '+', '£000', 0, NULL),
    ('FIN0100', 'TAC11 Finance & other', 'Compensation paid to cover debt recovery costs under this legislation', '+', '£000', 0, NULL),
    ('SCI1100A', 'TAC11 Finance & other', 'Gains on disposal of property, plant and equipment (sale)', '+', '£000', 0, NULL),
    ('SCI1100B', 'TAC11 Finance & other', 'Gains on disposal of PPE from creation of a finance lease (lessor)', '+', '£000', 0, NULL),
    ('SCI1110', 'TAC11 Finance & other', 'Gains on disposal of intangible assets (sale)', '+', '£000', 0, NULL),
    ('SCI1115A', 'TAC11 Finance & other', 'Gains on disposal of right of use assets (creation of a sublease)', '+', '£000', 0, NULL),
    ('SCI1115B', 'TAC11 Finance & other', 'Gains on disposal of right of use assets (lease termination - lessee)', '+', '£000', 0, NULL),
    ('SCI1120', 'TAC11 Finance & other', 'Gains on disposal of investment properties (sale)', '+', '£000', 0, NULL),
    ('SCI1130A', 'TAC11 Finance & other', 'Gain on disposal of financial assets held at amortised cost', '+', '£000', 0, NULL),
    ('SCI1130B', 'TAC11 Finance & other', 'Gain on disposal of other financial assets / investments', '+', '£000', 0, NULL),
    ('SCI1140', 'TAC11 Finance & other', 'Gains on disposal of assets held for sale', '+', '£000', 0, NULL),
    ('SCI1150B', 'TAC11 Finance & other', 'Losses on disposal of property, plant and equipment (sale or other derecognition)', '-', '£000', 0, NULL),
    ('SCI1150C', 'TAC11 Finance & other', 'Losses on disposal of PPE from creation of a finance lease (lessor)', '-', '£000', 0, NULL),
    ('SCI1160', 'TAC11 Finance & other', 'Losses on disposal of intangible assets (sale or other derecognition)', '-', '£000', 0, NULL),
    ('SCI1165A', 'TAC11 Finance & other', 'Losses on disposal of right of use assets (creation of a sublease)', '-', '£000', 0, NULL),
    ('SCI1165B', 'TAC11 Finance & other', 'Losses on disposal of right of use assets (lease termination - lessee)', '-', '£000', 0, NULL),
    ('SCI1170', 'TAC11 Finance & other', 'Losses on disposal of investment properties (sale or other derecognition)', '-', '£000', 0, NULL),
    ('SCI1180A', 'TAC11 Finance & other', 'Losses disposal of financial assets held at amortised cost', '-', '£000', 0, NULL),
    ('SCI1180B', 'TAC11 Finance & other', 'Losses on disposal of other financial assets / investments', '-', '£000', 0, NULL),
    ('SCI1190', 'TAC11 Finance & other', 'Losses on disposal of assets held for sale', '-', '£000', 0, NULL),
    ('SCI1191', 'TAC11 Finance & other', 'Losses on disposal of peppercorn leased assets (new peppercorn lease as lessor, terminated peppercorn lease as lessee)', '-', '£000', 0, NULL),
    ('SCI1150A', 'TAC11 Finance & other', 'Loss recognised on return of donated COVID assets to DHSC (comparative only)', '-', '£000', 0, NULL),
    ('FIN0110', 'TAC11 Finance & other', 'Gains / losses on disposal of charitable fund assets', '+/-', '£000', 0, NULL),
    ('SCI1200', 'TAC11 Finance & other', 'Total gains/(losses) on disposal of assets', '+/-', '£000', 1, NULL),
    ('SCI1201', 'TAC11 Finance & other', 'Gains/(losses) on foreign exchange', '+/-', '£000', 0, NULL),
    ('SCI0220A', 'TAC11 Finance & other', 'Fair value gains/(losses) on investment properties', '+/-', '£000', 0, NULL),
    ('SCI0220B', 'TAC11 Finance & other', 'Fair value gains/(losses) on financial assets / investments', '+/-', '£000', 0, NULL),
    ('FIN0120', 'TAC11 Finance & other', 'Fair value gains/(losses) on charitable fund investments & investment properties', '+/-', '£000', 0, NULL),
    ('SCI0220C', 'TAC11 Finance & other', 'Fair value gains/(losses) on financial liabilities', '+/-', '£000', 0, NULL),
    ('SCI0220D', 'TAC11 Finance & other', 'Recycling gains/(losses) on disposal of financial assets mandated as FV through OCI', '+/-', '£000', 0, NULL),
    ('FIN0130', 'TAC11 Finance & other', 'Recycling gains/(losses) on disposal of charitable fund financial assets mandated as FV through OCI', '+/-', '£000', 0, NULL),
    ('FIN0133', 'TAC11 Finance & other', 'Gains/(losses) on remeasurement of finance lease receivables (lessor)', '+/-', '£000', 0, NULL),
    ('FIN0134', 'TAC11 Finance & other', 'Gains/(losses) on termination of finance leases (lessor)', '+/-', '£000', 0, NULL),
    ('FIN0135', 'TAC11 Finance & other', 'Loss associated with loss of controlling interest in charitable fund', '-', '£000', 0, NULL),
    ('SCI1203', 'TAC11 Finance & other', 'Other gains/(losses)', '+/-', '£000', 0, NULL),
    ('SCI1205', 'TAC11 Finance & other', 'Total other gains/(losses)', '+/-', '£000', 1, NULL),
    ('FIN0140', 'TAC11 Finance & other', 'Operating income of discontinued operations', '+', '£000', 0, NULL),
    ('FIN0150', 'TAC11 Finance & other', 'Operating expenses of discontinued operations', '-', '£000', 0, NULL),
    ('FIN0160', 'TAC11 Finance & other', 'Gain on disposal of discontinued operations', '+', '£000', 0, NULL),
    ('FIN0170', 'TAC11 Finance & other', '(Loss) on disposal of discontinued operations', '-', '£000', 0, NULL),
    ('FIN0180', 'TAC11 Finance & other', 'Corporation tax expense attributable to discontinued operations', '+/-', '£000', 0, NULL),
    ('FIN0190', 'TAC11 Finance & other', 'Total', '+/-', '£000', 1, NULL);

-- TAC12 Impairment
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('IMP0010', 'TAC12 Impairment', 'Loss or damage resulting from normal operations', '+/-', '£000', 0, NULL),
    ('IMP0015', 'TAC12 Impairment', 'Over specification of assets', '+/-', '£000', 0, NULL),
    ('IMP0020', 'TAC12 Impairment', 'Abandonment of assets in the course of construction', '+/-', '£000', 0, NULL),
    ('IMP0025', 'TAC12 Impairment', 'Unforeseen obsolescence', '+/-', '£000', 0, NULL),
    ('IMP0030', 'TAC12 Impairment', 'Loss as a result of a catastrophe', '+/-', '£000', 0, NULL),
    ('IMP0035', 'TAC12 Impairment', 'Other', '+/-', '£000', 0, NULL),
    ('IMP0040', 'TAC12 Impairment', 'Changes in market price', '+/-', '£000', 0, NULL),
    ('IMP0044', 'TAC12 Impairment', 'Impairments of charitable fund assets', '+/-', '£000', 0, NULL),
    ('IMP0045', 'TAC12 Impairment', 'Total impairments and (reversals) charged to operating surplus / deficit', '+/-', '£000', 1, NULL),
    ('IMP0050', 'TAC12 Impairment', 'Total net impairments charged to revaluation reserve', '+/-', '£000', 1, NULL),
    ('IMP0055', 'TAC12 Impairment', 'Total impairments and (reversals)', '+/-', '£000', 1, NULL);

-- TAC13 Intangibles
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('INT0010', 'TAC13 Intangibles', 'Valuation / gross cost at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('INT0040', 'TAC13 Intangibles', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('INT0050', 'TAC13 Intangibles', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('INT0060', 'TAC13 Intangibles', 'Additions - purchased / internally generated', '+', '£000', 0, NULL),
    ('INT0080', 'TAC13 Intangibles', 'Additions - donations of physical assets (non-cash)', '+', '£000', 0, NULL),
    ('INT0090', 'TAC13 Intangibles', 'Additions - assets purchased from cash donations/grants', '+', '£000', 0, NULL),
    ('INT0095', 'TAC13 Intangibles', 'Transfer of donated assets (non-cash) from consolidated charitable fund to trust', '+', '£000', 0, NULL),
    ('INT0100', 'TAC13 Intangibles', 'Impairments charged to operating expenses', '-', '£000', 0, NULL),
    ('INT0110', 'TAC13 Intangibles', 'Impairments charged to the revaluation reserve', '-', '£000', 0, NULL),
    ('INT0120', 'TAC13 Intangibles', 'Reversal of impairments credited to operating expenses', '+', '£000', 0, NULL),
    ('INT0130', 'TAC13 Intangibles', 'Reversal of impairments credited to the revaluation reserve', '+', '£000', 0, NULL),
    ('INT0140', 'TAC13 Intangibles', 'Revaluations', '+/-', '£000', 0, NULL),
    ('INT0145', 'TAC13 Intangibles', 'Remeasurements - retranslation gains / (losses) on foreign operations', '+/-', '£000', 0, NULL),
    ('INT0150', 'TAC13 Intangibles', 'Reclassifications', '+/-', '£000', 0, NULL),
    ('INT0160', 'TAC13 Intangibles', 'Transfers to/from assets held for sale and assets in disposal groups', '+/-', '£000', 0, NULL),
    ('INT0170', 'TAC13 Intangibles', 'Disposals/derecognition', '-', '£000', 0, NULL),
    ('INT0180', 'TAC13 Intangibles', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('INT0190', 'TAC13 Intangibles', 'Valuation/gross cost at 31 March 2024', '+', '£000', 0, NULL),
    ('INT0200', 'TAC13 Intangibles', 'Accumulated amortisation at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('INT0230', 'TAC13 Intangibles', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('INT0240', 'TAC13 Intangibles', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('INT0250', 'TAC13 Intangibles', 'Provided during the year', '+', '£000', 0, NULL),
    ('INT0255', 'TAC13 Intangibles', 'Transfer of donated assets (non-cash) from consolidated charitable fund to trust', '-', '£000', 0, NULL),
    ('INT0260', 'TAC13 Intangibles', 'Impairments charged to operating expenses', '+', '£000', 0, NULL),
    ('INT0270', 'TAC13 Intangibles', 'Impairments charged to the revaluation reserve', '+', '£000', 0, NULL),
    ('INT0280', 'TAC13 Intangibles', 'Reversal of impairments credited to operating expenses', '-', '£000', 0, NULL),
    ('INT0290', 'TAC13 Intangibles', 'Reversal of impairments credited to the revaluation reserve', '-', '£000', 0, NULL),
    ('INT0300', 'TAC13 Intangibles', 'Revaluations', '+/-', '£000', 0, NULL),
    ('INT0305', 'TAC13 Intangibles', 'Remeasurements - retranslation gains / (losses) on foreign operations', '+/-', '£000', 0, NULL),
    ('INT0310', 'TAC13 Intangibles', 'Reclassifications', '+/-', '£000', 0, NULL),
    ('INT0320', 'TAC13 Intangibles', 'Transfers to/from assets held for sale and assets in disposal groups', '+/-', '£000', 0, NULL),
    ('INT0330', 'TAC13 Intangibles', 'Disposals/derecognition', '-', '£000', 0, NULL),
    ('INT0340', 'TAC13 Intangibles', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('INT0350', 'TAC13 Intangibles', 'Accumulated amortisation at 31 March 2024', '+', '£000', 0, NULL),
    ('INT0360', 'TAC13 Intangibles', 'Net book value at 31 March 2024', '+', '£000', 0, NULL),
    ('INT0020', 'TAC13 Intangibles', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('INT0030', 'TAC13 Intangibles', 'Valuation / gross cost at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('INT0035', 'TAC13 Intangibles', 'Reclassification of existing finance leased assets to right of use assets on 1 April 2022', '-', '£000', 0, NULL),
    ('INT0210', 'TAC13 Intangibles', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('INT0220', 'TAC13 Intangibles', 'Accumulated amortisation at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('INT0225', 'TAC13 Intangibles', 'Reclassification of existing finance leased assets to right of use assets on 1 April 2022', '-', '£000', 0, NULL),
    ('INT0390', 'TAC13 Intangibles', 'Information technology', '+', '£000', 0, NULL),
    ('INT0400', 'TAC13 Intangibles', 'Development expenditure', '+', '£000', 0, NULL),
    ('INT0410', 'TAC13 Intangibles', 'Websites', '+', '£000', 0, NULL),
    ('INT0430', 'TAC13 Intangibles', 'Software licences', '+', '£000', 0, NULL),
    ('INT0440', 'TAC13 Intangibles', 'Licences & trademarks', '+', '£000', 0, NULL),
    ('INT0450', 'TAC13 Intangibles', 'Patents', '+', '£000', 0, NULL),
    ('INT0460', 'TAC13 Intangibles', 'Other (purchased)', '+', '£000', 0, NULL),
    ('INT0470', 'TAC13 Intangibles', 'Goodwill', '+', '£000', 0, NULL);

-- TAC14 PPE
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('PPE0010', 'TAC14 PPE', 'Valuation / gross cost at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('PPE0040', 'TAC14 PPE', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('PPE0050', 'TAC14 PPE', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('PPE0060', 'TAC14 PPE', 'Additions - purchased (including capital lifecycle additions)', '+', '£000', 0, NULL),
    ('PPE0070', 'TAC14 PPE', 'Additions - IFRIC 12 scheme assets (excluding lifecycle)', '+', '£000', 0, NULL),
    ('PPE0080', 'TAC14 PPE', 'Additions - donations of physical assets (non-cash)', '+', '£000', 0, NULL),
    ('PPE0090', 'TAC14 PPE', 'Additions - assets purchased from cash donations/grants', '+', '£000', 0, NULL),
    ('PPE0095', 'TAC14 PPE', 'Transfer of donated assets (non-cash) from consolidated charitable fund to trust', '+', '£000', 0, NULL),
    ('PPE0096', 'TAC14 PPE', 'Additions - assets re-recognised at the end of an intra-government finance lease (trust was lessor)', '+', '£000', 0, NULL),
    ('PPE0097', 'TAC14 PPE', 'Additions - assets re-recognised at the end of an external to government finance lease (trust was lessor)', '+', '£000', 0, NULL),
    ('PPE0100', 'TAC14 PPE', 'Impairments charged to operating expenses', '-', '£000', 0, NULL),
    ('PPE0110', 'TAC14 PPE', 'Impairments charged to the revaluation reserve', '-', '£000', 0, NULL),
    ('PPE0120', 'TAC14 PPE', 'Reversal of impairments credited to operating expenses', '+', '£000', 0, NULL),
    ('PPE0130', 'TAC14 PPE', 'Reversal of impairments credited to the revaluation reserve', '+', '£000', 0, NULL),
    ('PPE0140', 'TAC14 PPE', 'Revaluations', '+/-', '£000', 0, NULL),
    ('PPE0145', 'TAC14 PPE', 'Remeasurements - retranslation gains / (losses) on foreign operations', '+/-', '£000', 0, NULL),
    ('PPE0150', 'TAC14 PPE', 'Reclassifications', '+/-', '£000', 0, NULL),
    ('PPE0160', 'TAC14 PPE', 'Transfers to/from assets held for sale and assets in disposal groups', '+/-', '£000', 0, NULL),
    ('PPE0170', 'TAC14 PPE', 'Disposals/derecognition', '-', '£000', 0, NULL),
    ('PPE0172', 'TAC14 PPE', 'Disposals - new finance lease (lessor)', '-', '£000', 0, NULL),
    ('PPE0151', 'TAC14 PPE', 'Reclassifications from RoU assets where ownership has transferred', '+', '£000', 0, NULL),
    ('PPE0180', 'TAC14 PPE', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('PPE0190', 'TAC14 PPE', 'Valuation/gross cost at 31 March 2024', '+', '£000', 0, NULL),
    ('PPE0200', 'TAC14 PPE', 'Accumulated depreciation at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('PPE0230', 'TAC14 PPE', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('PPE0240', 'TAC14 PPE', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('PPE0250', 'TAC14 PPE', 'Provided during the year', '+', '£000', 0, NULL),
    ('PPE0255', 'TAC14 PPE', 'Transfer of donated assets (non-cash) from consolidated charitable fund to trust', '-', '£000', 0, NULL),
    ('PPE0260', 'TAC14 PPE', 'Impairments charged to operating expenses', '+', '£000', 0, NULL),
    ('PPE0270', 'TAC14 PPE', 'Impairments charged to the revaluation reserve', '+', '£000', 0, NULL),
    ('PPE0280', 'TAC14 PPE', 'Reversal of impairments credited to operating expenses', '-', '£000', 0, NULL),
    ('PPE0290', 'TAC14 PPE', 'Reversal of impairments credited to the revaluation reserve', '-', '£000', 0, NULL),
    ('PPE0300', 'TAC14 PPE', 'Revaluations', '+/-', '£000', 0, NULL),
    ('PPE0305', 'TAC14 PPE', 'Remeasurements - retranslation gains / (losses) on foreign operations', '+/-', '£000', 0, NULL),
    ('PPE0310', 'TAC14 PPE', 'Reclassifications', '+/-', '£000', 0, NULL),
    ('PPE0320', 'TAC14 PPE', 'Transfers to/from assets held for sale and assets in disposal groups', '+/-', '£000', 0, NULL),
    ('PPE0330', 'TAC14 PPE', 'Disposals/derecognition', '-', '£000', 0, NULL),
    ('PPE0332', 'TAC14 PPE', 'Disposals - new finance lease (lessor)', '-', '£000', 0, NULL),
    ('PPE0311', 'TAC14 PPE', 'Reclassifications from RoU assets where ownership has transferred', '-', '£000', 0, NULL),
    ('PPE0340', 'TAC14 PPE', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('PPE0350', 'TAC14 PPE', 'Accumulated depreciation at 31 March 2024', '+', '£000', 0, NULL),
    ('PPE0020', 'TAC14 PPE', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('PPE0030', 'TAC14 PPE', 'Valuation / gross cost at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('PPE0035', 'TAC14 PPE', 'Reclassification of existing finance leased assets to right of use assets on 1 April 2022', '-', '£000', 0, NULL),
    ('PPE0175', 'TAC14 PPE', 'Derecognition - COVID equipment returned to DHSC', '-', '£000', 0, NULL),
    ('PPE0210', 'TAC14 PPE', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('PPE0220', 'TAC14 PPE', 'Accumulated depreciation at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('PPE0225', 'TAC14 PPE', 'Reclassification of existing finance leased assets to right of use assets on 1 April 2022', '-', '£000', 0, NULL),
    ('PPE0335', 'TAC14 PPE', 'Derecognition - COVID equipment returned to DHSC', '-', '£000', 0, NULL),
    ('PPE0360', 'TAC14 PPE', 'Owned - purchased', '+', '£000', 0, NULL),
    ('PPE0380', 'TAC14 PPE', 'On-SoFP PFI contracts and other service concession arrangements', '+', '£000', 0, NULL),
    ('PPE0390', 'TAC14 PPE', 'Off-SoFP PFI residual interests', '+', '£000', 0, NULL),
    ('PPE0410', 'TAC14 PPE', 'Owned - donated / granted', '+', '£000', 0, NULL),
    ('PPE0420', 'TAC14 PPE', 'NBV total at 31 March 2024', '+', '£000', 0, NULL),
    ('PPE0490', 'TAC14 PPE', 'Land', '+', '£000', 0, NULL),
    ('PPE0500', 'TAC14 PPE', 'Buildings excluding dwellings', '+', '£000', 0, NULL),
    ('PPE0510', 'TAC14 PPE', 'Dwellings', '+', '£000', 0, NULL),
    ('PPE0520', 'TAC14 PPE', 'Plant & machinery', '+', '£000', 0, NULL),
    ('PPE0530', 'TAC14 PPE', 'Transport equipment', '+', '£000', 0, NULL),
    ('PPE0540', 'TAC14 PPE', 'Information technology', '+', '£000', 0, NULL),
    ('PPE0550', 'TAC14 PPE', 'Furniture & fittings', '+', '£000', 0, NULL);

-- TAC14A RoU Assets
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('ROU0010', 'TAC14A RoU Assets', 'Valuation / gross cost at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('ROU0040', 'TAC14A RoU Assets', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('ROU0050', 'TAC14A RoU Assets', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('ROU0070', 'TAC14A RoU Assets', 'Additions - lease liability', '+', '£000', 0, NULL),
    ('ROU0071', 'TAC14A RoU Assets', 'Additions - up front lease payments (before or on commencement)', '+', '£000', 0, NULL),
    ('ROU0072', 'TAC14A RoU Assets', 'Additions - initial direct costs of obtaining a lease', '+', '£000', 0, NULL),
    ('ROU0073', 'TAC14A RoU Assets', 'Additions - cash lease incentives (reduce the RoU addition value)', '-', '£000', 0, NULL),
    ('ROU0080', 'TAC14A RoU Assets', 'Additions - peppercorn leases', '+', '£000', 0, NULL),
    ('ROU0081', 'TAC14A RoU Assets', 'Re-recognition of RoU asset at end of sublease - intra-gov sublease', '+', '£000', 0, NULL),
    ('ROU0082', 'TAC14A RoU Assets', 'Re-recognition of RoU asset at end of sublease - ext to gov sublease', '+', '£000', 0, NULL),
    ('ROU0096', 'TAC14A RoU Assets', 'Remeasurements of the lease liability', '+/-', '£000', 0, NULL),
    ('ROU0097', 'TAC14A RoU Assets', 'Dilapidation provisions arising (capitalised in RoU asset)', '+', '£000', 0, NULL),
    ('ROU0098', 'TAC14A RoU Assets', 'Dilapidation provisions reversed unused', '-', '£000', 0, NULL),
    ('ROU0099', 'TAC14A RoU Assets', 'Dilapidation provisions - change in discount rate', '+/-', '£000', 0, NULL),
    ('ROU0100', 'TAC14A RoU Assets', 'Impairments charged to operating expenses', '-', '£000', 0, NULL),
    ('ROU0110', 'TAC14A RoU Assets', 'Impairments charged to the revaluation reserve', '-', '£000', 0, NULL),
    ('ROU0120', 'TAC14A RoU Assets', 'Reversal of impairments credited to operating expenses', '+', '£000', 0, NULL),
    ('ROU0130', 'TAC14A RoU Assets', 'Reversal of impairments credited to the revaluation reserve', '+', '£000', 0, NULL),
    ('ROU0140', 'TAC14A RoU Assets', 'Revaluations', '+/-', '£000', 0, NULL),
    ('ROU0145', 'TAC14A RoU Assets', 'Remeasurements - retranslation gains / (losses) on foreign operations', '+/-', '£000', 0, NULL),
    ('ROU0150', 'TAC14A RoU Assets', 'Reclassifications', '+/-', '£000', 0, NULL),
    ('ROU0171', 'TAC14A RoU Assets', 'Disposals/derecognition - lease termination', '-', '£000', 0, NULL),
    ('ROU0172', 'TAC14A RoU Assets', 'Disposals/derecognition - peppercorn lease termination', '-', '£000', 0, NULL),
    ('ROU0173', 'TAC14A RoU Assets', 'Disposals/derecognition - new sublease (leased to intra-government body)', '-', '£000', 0, NULL),
    ('ROU0174', 'TAC14A RoU Assets', 'Disposals/derecognition - new sublease (leased to external to government)', '-', '£000', 0, NULL),
    ('ROU0175', 'TAC14A RoU Assets', 'Disposals/derecognition - new peppercorn sublease (intra-government)', '-', '£000', 0, NULL),
    ('ROU0176', 'TAC14A RoU Assets', 'Disposals/derecognition - new peppercorn sublease (ext to government)', '-', '£000', 0, NULL),
    ('ROU0151', 'TAC14A RoU Assets', 'Reclassifications to PPE where ownership has transferred', '-', '£000', 0, NULL),
    ('ROU0180', 'TAC14A RoU Assets', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('ROU0190', 'TAC14A RoU Assets', 'Valuation/gross cost at 31 March 2024', '+', '£000', 0, NULL),
    ('ROU0200', 'TAC14A RoU Assets', 'Accumulated depreciation at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('ROU0230', 'TAC14A RoU Assets', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('ROU0240', 'TAC14A RoU Assets', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('ROU0250', 'TAC14A RoU Assets', 'Provided during the year - right of use asset', '+', '£000', 0, NULL),
    ('ROU0251', 'TAC14A RoU Assets', 'Provided during the year - peppercorn leased asset', '+', '£000', 0, NULL),
    ('ROU0260', 'TAC14A RoU Assets', 'Impairments charged to operating expenses', '+', '£000', 0, NULL),
    ('ROU0270', 'TAC14A RoU Assets', 'Impairments charged to the revaluation reserve', '+', '£000', 0, NULL),
    ('ROU0280', 'TAC14A RoU Assets', 'Reversal of impairments credited to operating expenses', '-', '£000', 0, NULL),
    ('ROU0290', 'TAC14A RoU Assets', 'Reversal of impairments credited to the revaluation reserve', '-', '£000', 0, NULL),
    ('ROU0300', 'TAC14A RoU Assets', 'Revaluations', '+/-', '£000', 0, NULL),
    ('ROU0305', 'TAC14A RoU Assets', 'Remeasurements - retranslation gains / (losses) on foreign operations', '+/-', '£000', 0, NULL),
    ('ROU0310', 'TAC14A RoU Assets', 'Reclassifications', '+/-', '£000', 0, NULL),
    ('ROU0331', 'TAC14A RoU Assets', 'Disposals/derecognition - lease termination', '-', '£000', 0, NULL),
    ('ROU0332', 'TAC14A RoU Assets', 'Disposals/derecognition - peppercorn lease termination', '-', '£000', 0, NULL),
    ('ROU0333', 'TAC14A RoU Assets', 'Disposals/derecognition - new sublease (leased to intra-government body)', '-', '£000', 0, NULL),
    ('ROU0334', 'TAC14A RoU Assets', 'Disposals/derecognition - new sublease (leased to external to government)', '-', '£000', 0, NULL),
    ('ROU0335', 'TAC14A RoU Assets', 'Disposals/derecognition - new peppercorn sublease (intra-government)', '-', '£000', 0, NULL),
    ('ROU0336', 'TAC14A RoU Assets', 'Disposals/derecognition - new peppercorn sublease (ext to government)', '-', '£000', 0, NULL),
    ('ROU0311', 'TAC14A RoU Assets', 'Reclassifications to PPE where ownership has transferred', '-', '£000', 0, NULL),
    ('ROU0340', 'TAC14A RoU Assets', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('ROU0350', 'TAC14A RoU Assets', 'Accumulated depreciation at 31 March 2024', '+', '£000', 0, NULL),
    ('ROU0360', 'TAC14A RoU Assets', 'Net book value at 31 March 2024', '+', '£000', 0, NULL),
    ('ROU0361', 'TAC14A RoU Assets', 'Leased from other NHS providers', '+', '£000', 0, NULL),
    ('ROU0362', 'TAC14A RoU Assets', 'Leased from other DHSC group bodies', '+', '£000', 0, NULL);

-- TAC15 Investments & groups
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('IGR0020', 'TAC15 Investments & groups', 'Prior period adjustments', '+/-', '£000', 0, NULL),
    ('IGR0034', 'TAC15 Investments & groups', 'Reclassification of existing finance leased assets classified as investment property on 1 April 2022', '+', '£000', 0, NULL),
    ('IGR0035', 'TAC15 Investments & groups', 'Recognition of right of use assets for existing operating leases on initial application of IFRS 16 on 1 April 2022', '+', '£000', 0, NULL),
    ('IGR0040', 'TAC15 Investments & groups', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('IGR0050', 'TAC15 Investments & groups', 'Transfers by absorption', '+', '£000', 0, NULL),
    ('IGR0060', 'TAC15 Investments & groups', 'Additions', '+', '£000', 0, NULL),
    ('IGR0062', 'TAC15 Investments & groups', 'Remeasurements of the lease liability', '+/-', '£000', 0, NULL),
    ('IGR0065', 'TAC15 Investments & groups', 'Capitalised dilapidation provisions', '+/-', '£000', 0, NULL),
    ('IGR0080', 'TAC15 Investments & groups', 'Fair value gains [taken to I&E]', '+', '£000', 0, NULL),
    ('IGR0090', 'TAC15 Investments & groups', 'Fair value losses (impairment) [taken to I&E]', '-', '£000', 0, NULL),
    ('IGR0100', 'TAC15 Investments & groups', 'Reclassifications to/from PPE', '+/-', '£000', 0, NULL),
    ('IGR0105', 'TAC15 Investments & groups', 'Reclassifications to/from RoU assets', '+/-', '£000', 0, NULL),
    ('IGR0110', 'TAC15 Investments & groups', 'Transfers to/from assets held for sale and assets in disposal groups', '+/-', '£000', 0, NULL),
    ('IGR0120', 'TAC15 Investments & groups', 'Disposals', '-', '£000', 0, NULL),
    ('IGR0130', 'TAC15 Investments & groups', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('IGR0140', 'TAC15 Investments & groups', 'Carrying value at 31 March', '+', '£000', 0, NULL),
    ('IGR0200', 'TAC15 Investments & groups', 'Prior period adjustments', '+/-', '£000', 0, NULL),
    ('IGR0220', 'TAC15 Investments & groups', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('IGR0230', 'TAC15 Investments & groups', 'Transfers by absorption', '+', '£000', 0, NULL),
    ('IGR0240', 'TAC15 Investments & groups', 'Additions', '+', '£000', 0, NULL),
    ('IGR0250', 'TAC15 Investments & groups', 'Share of profit/(loss)', '+/-', '£000', 0, NULL),
    ('IGR0260', 'TAC15 Investments & groups', 'Impairments', '-', '£000', 0, NULL),
    ('IGR0270', 'TAC15 Investments & groups', 'Reversal of impairment', '+', '£000', 0, NULL),
    ('IGR0280', 'TAC15 Investments & groups', 'Transfers to/from assets held for sale and assets in disposal groups', '+/-', '£000', 0, NULL),
    ('IGR0290', 'TAC15 Investments & groups', 'Disbursements / dividends received', '-', '£000', 0, NULL),
    ('IGR0300', 'TAC15 Investments & groups', 'Disposals', '-', '£000', 0, NULL),
    ('IGR0310', 'TAC15 Investments & groups', 'Share of Other Comprehensive Income recognised by joint ventures/associates', '+/-', '£000', 0, NULL),
    ('IGR0320', 'TAC15 Investments & groups', 'Other equity movements (translation gains/losses)', '+/-', '£000', 0, NULL),
    ('IGR0330', 'TAC15 Investments & groups', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('IGR0340', 'TAC15 Investments & groups', 'Carrying value at 31 March', '+', '£000', 0, NULL),
    ('IGR0360', 'TAC15 Investments & groups', 'Prior period adjustments', '+/-', '£000', 0, NULL),
    ('IGR0380', 'TAC15 Investments & groups', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('IGR0390', 'TAC15 Investments & groups', 'Transfers by absorption', '+', '£000', 0, NULL),
    ('IGR0400', 'TAC15 Investments & groups', 'Additions', '+', '£000', 0, NULL),
    ('IGR0410', 'TAC15 Investments & groups', 'Fair value gains [taken to I&E] (for assets held at FV through I&E)', '+', '£000', 0, NULL),
    ('IGR0420', 'TAC15 Investments & groups', 'Fair value losses [taken to I&E] (for assets held at FV through I&E)', '-', '£000', 0, NULL),
    ('IGR0430', 'TAC15 Investments & groups', 'Fair value movements [taken to OCI] (for financial assets mandated as FV through OCI)', '+/-', '£000', 0, NULL),
    ('IGR0435', 'TAC15 Investments & groups', 'Fair value movements [taken to OCI] (for equity instruments designated as FV through OCI)', '+/-', '£000', 0, NULL),
    ('IGR0439', 'TAC15 Investments & groups', '(Increase)/decrease in credit loss allowance (stages 1 and 2)', NULL, '£000', 0, NULL),
    ('IGR0440', 'TAC15 Investments & groups', 'Net impairments on credit impaired financial assets (stage 3 credit losses)', NULL, '£000', 0, NULL),
    ('IGR0460', 'TAC15 Investments & groups', 'Transfers to/from assets held for sale and assets in disposal groups', '+/-', '£000', 0, NULL),
    ('IGR0470', 'TAC15 Investments & groups', 'Amortisation at the effective interest rate (assets held at amortised cost only where applicable)', '+/-', '£000', 0, NULL),
    ('IGR0475', 'TAC15 Investments & groups', 'Current portion of loans receivable transferred to current financial assets', '-', '£000', 0, NULL),
    ('IGR0480', 'TAC15 Investments & groups', 'Disposals', '-', '£000', 0, NULL),
    ('IGR0490', 'TAC15 Investments & groups', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('IGR0500', 'TAC15 Investments & groups', 'Carrying value at 31 March', '+', '£000', 0, NULL),
    ('IGR0505', 'TAC15 Investments & groups', 'Loans receivable within 12 months transferred from non-current financial assets', '+', '£000', 0, NULL),
    ('IGR0510', 'TAC15 Investments & groups', 'NLF deposits (where not considered to be cash equivalents)', '+', '£000', 0, NULL),
    ('IGR0515', 'TAC15 Investments & groups', 'Other current financial assets', '+', '£000', 0, NULL),
    ('IGR0520', 'TAC15 Investments & groups', 'Total current investments / financial assets at 31 March', '+', '£000', 1, NULL);

-- TAC16 AHFS
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('AHS0010', 'TAC16 AHFS', 'NBV of non-current assets for sale and assets in disposal groups at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('AHS0040', 'TAC16 AHFS', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('AHS0050', 'TAC16 AHFS', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('AHS0060', 'TAC16 AHFS', 'Plus assets classified as available for sale in the year', '+', '£000', 0, NULL),
    ('AHS0070', 'TAC16 AHFS', 'Less assets sold in year', '-', '£000', 0, NULL),
    ('AHS0080', 'TAC16 AHFS', 'Less impairment of assets held for sale', '-', '£000', 0, NULL),
    ('AHS0090', 'TAC16 AHFS', 'Plus reversal of impairment of assets held for sale', '+', '£000', 0, NULL),
    ('AHS0100', 'TAC16 AHFS', 'Less assets no longer classified as held for sale, for reasons other than disposal by sale', '-', '£000', 0, NULL),
    ('AHS0110', 'TAC16 AHFS', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('AHS0120', 'TAC16 AHFS', 'NBV of non-current assets for sale and assets in disposal groups at 31 March 2024', '+', '£000', 0, NULL),
    ('AHS0020', 'TAC16 AHFS', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('AHS0030', 'TAC16 AHFS', 'NBV of non-current assets for sale and assets in disposal groups at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('AHS0130', 'TAC16 AHFS', 'Provisions', '+', '£000', 0, NULL),
    ('AHS0140', 'TAC16 AHFS', 'Trade and other payables', '+', '£000', 0, NULL),
    ('AHS0150', 'TAC16 AHFS', 'Other', '+', '£000', 0, NULL),
    ('AHS0160', 'TAC16 AHFS', 'Total', '+', '£000', 1, NULL);

-- TAC17 Inventories
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('INV0010', 'TAC17 Inventories', 'Carrying value at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('INV0040', 'TAC17 Inventories', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('INV0050', 'TAC17 Inventories', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('INV0060', 'TAC17 Inventories', 'Additions (purchased)', '+', '£000', 0, NULL),
    ('INV0061', 'TAC17 Inventories', 'Additions (donated) - from DHSC', '+', '£000', 0, NULL),
    ('INV0062', 'TAC17 Inventories', 'Additions (donated) - from NHS provider (purchased by DHSC)', '+', '£000', 0, NULL),
    ('INV0063', 'TAC17 Inventories', 'Additions (donated) - from NHS provider (purchased by provider) (unlocked on request)', '+', '£000', 0, NULL),
    ('INV0070', 'TAC17 Inventories', 'Inventories consumed (recognised in expenses)', '-', '£000', 0, NULL),
    ('INV0080', 'TAC17 Inventories', 'Write-down of inventories recognised as an expense', '-', '£000', 0, NULL),
    ('INV0090', 'TAC17 Inventories', 'Reversal of any write down of inventories', '+', '£000', 0, NULL),
    ('INV0100', 'TAC17 Inventories', 'Transfer (to) / from inventory work in progress', NULL, '£000', 0, NULL),
    ('INV0110', 'TAC17 Inventories', 'Other', '+/-', '£000', 0, NULL),
    ('INV0115', 'TAC17 Inventories', 'Movement in charitable funds inventories', '+/-', '£000', 0, NULL),
    ('INV0120', 'TAC17 Inventories', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('INV0130', 'TAC17 Inventories', 'Carrying value at 31 March 2024', '+', '£000', 0, NULL),
    ('INV0140', 'TAC17 Inventories', 'Held at lower of cost and NRV', '+', '£000', 0, NULL),
    ('INV0150', 'TAC17 Inventories', 'Held at fair value less costs to sell', '+', '£000', 0, NULL),
    ('INV0020', 'TAC17 Inventories', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('INV0030', 'TAC17 Inventories', 'Carrying value at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('INV0060A', 'TAC17 Inventories', 'Additions (donated)', '+', '£000', 0, NULL);

-- TAC18 Receivables
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('REC0001', 'TAC18 Receivables', 'Contract receivables (IFRS 15): invoiced', '+', '£000', 0, NULL),
    ('REC0002', 'TAC18 Receivables', 'Contract receivables (IFRS 15): not yet invoiced / non-invoiced', '+', '£000', 0, NULL),
    ('REC0005', 'TAC18 Receivables', 'Contract assets (IFRS 15)', '+', '£000', 0, NULL),
    ('REC0020', 'TAC18 Receivables', 'Capital receivables (including accrued capital related income)', '+', '£000', 0, NULL),
    ('REC0039', 'TAC18 Receivables', 'Allowance for impaired contract receivables / assets', '-', '£000', 0, NULL),
    ('REC0040', 'TAC18 Receivables', 'Allowance for impaired other receivables', '-', '£000', 0, NULL),
    ('REC0050', 'TAC18 Receivables', 'Deposits and advances', '+', '£000', 0, NULL),
    ('REC0060', 'TAC18 Receivables', 'Prepayments (revenue) [non-PFI]', '+', '£000', 0, NULL),
    ('REC0070', 'TAC18 Receivables', 'Prepayments (capital) [non-PFI]', '+', '£000', 0, NULL),
    ('REC0080', 'TAC18 Receivables', 'PFI prepayments - capital contributions', '+', '£000', 0, NULL),
    ('REC0090', 'TAC18 Receivables', 'PFI lifecycle prepayments (revenue)', '+', '£000', 0, NULL),
    ('REC0100', 'TAC18 Receivables', 'PFI lifecycle prepayments (capital)', '+', '£000', 0, NULL),
    ('REC0110', 'TAC18 Receivables', 'Interest receivable (excludes finance lease interest)', '+', '£000', 0, NULL),
    ('REC0119', 'TAC18 Receivables', 'Finance lease receivables - invoiced / due but not yet paid', '+', '£000', 0, NULL),
    ('REC0120', 'TAC18 Receivables', 'Finance lease receivables - not yet invoiced / not relating to current year', '+', '£000', 0, NULL),
    ('REC0125', 'TAC18 Receivables', 'Operating lease receivables', '+', '£000', 0, NULL),
    ('REC0130', 'TAC18 Receivables', 'PDC dividend receivable', '+', '£000', 0, NULL),
    ('REC0140', 'TAC18 Receivables', 'VAT receivable', '+', '£000', 0, NULL),
    ('REC0150', 'TAC18 Receivables', 'Corporation and other taxes receivable', '+', '£000', 0, NULL),
    ('REC0155', 'TAC18 Receivables', 'Clinician pension tax provision reimbursement funding from NHSE', '+', '£000', 0, NULL),
    ('REC0160', 'TAC18 Receivables', 'Other receivables', '+', '£000', 0, NULL),
    ('REC0165', 'TAC18 Receivables', 'NHS charitable funds: receivables', '+', '£000', 0, NULL),
    ('REC0170', 'TAC18 Receivables', 'Total current receivables', '+', '£000', 1, NULL),
    ('REC0171', 'TAC18 Receivables', 'Contract receivables (IFRS 15): invoiced', '+', '£000', 0, NULL),
    ('REC0172', 'TAC18 Receivables', 'Contract receivables (IFRS 15): not yet invoiced / non-invoiced', '+', '£000', 0, NULL),
    ('REC0175', 'TAC18 Receivables', 'Contract assets (IFRS 15)', '+', '£000', 0, NULL),
    ('REC0190', 'TAC18 Receivables', 'Capital receivables (including accrued capital related income)', '+', '£000', 0, NULL),
    ('REC0209', 'TAC18 Receivables', 'Allowance for impaired contract receivables / assets', '-', '£000', 0, NULL),
    ('REC0210', 'TAC18 Receivables', 'Allowance for impaired other receivables', '-', '£000', 0, NULL),
    ('REC0220', 'TAC18 Receivables', 'Deposits and advances', '+', '£000', 0, NULL),
    ('REC0230', 'TAC18 Receivables', 'Prepayments (revenue) [non-PFI]', '+', '£000', 0, NULL),
    ('REC0240', 'TAC18 Receivables', 'Prepayments (capital) [non-PFI]', '+', '£000', 0, NULL),
    ('REC0250', 'TAC18 Receivables', 'PFI prepayments - capital contributions', '+', '£000', 0, NULL),
    ('REC0260', 'TAC18 Receivables', 'PFI lifecycle prepayments (revenue)', '+', '£000', 0, NULL),
    ('REC0270', 'TAC18 Receivables', 'PFI lifecycle prepayments (capital)', '+', '£000', 0, NULL),
    ('REC0280', 'TAC18 Receivables', 'Interest receivable', '+', '£000', 0, NULL),
    ('REC0290', 'TAC18 Receivables', 'Finance lease receivables', '+', '£000', 0, NULL),
    ('REC0295', 'TAC18 Receivables', 'Operating lease receivables', '+', '£000', 0, NULL),
    ('REC0300', 'TAC18 Receivables', 'VAT receivable', '+', '£000', 0, NULL),
    ('REC0310', 'TAC18 Receivables', 'Corporation and other taxes receivable', '+', '£000', 0, NULL),
    ('REC0315', 'TAC18 Receivables', 'Clinician pension tax provision reimbursement funding from NHSE', '+', '£000', 0, NULL),
    ('REC0320', 'TAC18 Receivables', 'Other receivables', '+', '£000', 0, NULL),
    ('REC0325', 'TAC18 Receivables', 'NHS charitable funds: receivables', '+', '£000', 0, NULL),
    ('REC0330', 'TAC18 Receivables', 'Total non-current receivables', '+', '£000', 1, NULL),
    ('REC0335', 'TAC18 Receivables', 'Total receivables', '+', '£000', 1, NULL),
    ('REC0340', 'TAC18 Receivables', 'Current', '+', '£000', 0, NULL),
    ('REC0350', 'TAC18 Receivables', 'Non-current', '+', '£000', 0, NULL),
    ('REC1100', 'TAC18 Receivables', 'Allowance for credit losses at 1 April - brought forward', '+', '£000', 0, NULL),
    ('REC1110', 'TAC18 Receivables', 'Prior period adjustments', '+/-', '£000', 0, NULL),
    ('REC1120', 'TAC18 Receivables', 'Allowance for credit losses at 1 April - restated', '+', '£000', 0, NULL),
    ('REC1130', 'TAC18 Receivables', 'At start of period for new FTs', '+/-', '£000', 0, NULL),
    ('REC1140', 'TAC18 Receivables', 'Transfer by absorption', '+/-', '£000', 0, NULL),
    ('REC1150', 'TAC18 Receivables', 'New allowances arising', '+', '£000', 0, NULL),
    ('REC1160', 'TAC18 Receivables', 'Changes in the calculation of existing allowances', '+/-', '£000', 0, NULL),
    ('REC1170', 'TAC18 Receivables', 'Reversals of allowances (where receivable is collected in-year)', '-', '£000', 0, NULL),
    ('REC1180', 'TAC18 Receivables', 'Utilisation of allowances (where receivable is written off)', '-', '£000', 0, NULL),
    ('REC1190', 'TAC18 Receivables', 'Changes arising following modification of contractual cash flows', '+/-', '£000', 0, NULL),
    ('REC1200', 'TAC18 Receivables', 'Foreign exchange and other changes', '+/-', '£000', 0, NULL),
    ('REC1210', 'TAC18 Receivables', 'Transfer to FT upon authorisation', '+/-', '£000', 0, NULL),
    ('REC1220', 'TAC18 Receivables', 'Total allowance for credit losses at 31 March', '+', '£000', 1, NULL),
    ('REC1230', 'TAC18 Receivables', 'Loss / (gain) recognised in expenditure', '+', '£000', 0, NULL),
    ('REC0590', 'TAC18 Receivables', 'Other assets', '+', '£000', 0, NULL),
    ('REC0600', 'TAC18 Receivables', 'Short term PFI receivable', '+', '£000', 0, NULL),
    ('REC0610', 'TAC18 Receivables', 'Total other current assets', '+', '£000', 1, NULL),
    ('REC0620', 'TAC18 Receivables', 'Net defined benefit pension scheme asset', '+', '£000', 0, NULL),
    ('REC0630', 'TAC18 Receivables', 'Other assets', '+', '£000', 0, NULL),
    ('REC0640', 'TAC18 Receivables', 'Total other non-current assets', '+', '£000', 1, NULL),
    ('REC1400', 'TAC18 Receivables', '- not later than one year;', '+', '£000', 0, NULL),
    ('REC1410', 'TAC18 Receivables', '- later than one year and not later than two years;', '+', '£000', 0, NULL),
    ('REC1420', 'TAC18 Receivables', '- later than two years and not later than three years;', '+', '£000', 0, NULL),
    ('REC1430', 'TAC18 Receivables', '- later than three years and not later than four years;', '+', '£000', 0, NULL),
    ('REC1440', 'TAC18 Receivables', '- later than four years and not later than five years;', '+', '£000', 0, NULL),
    ('REC1450', 'TAC18 Receivables', '- later than five years.', '+', '£000', 0, NULL),
    ('REC1460', 'TAC18 Receivables', 'Total future finance lease payments to be received', '+', '£000', 1, NULL),
    ('REC1470', 'TAC18 Receivables', 'Estimated value of unguaranteed residual interest', '+', '£000', 0, NULL),
    ('REC1480', 'TAC18 Receivables', 'Unearned interest income', '-', '£000', 0, NULL),
    ('REC1490', 'TAC18 Receivables', 'Allowance for uncollectable lease payments', '-', '£000', 0, NULL),
    ('REC1500', 'TAC18 Receivables', 'Net investment in lease (net lease receivable)', '+', '£000', 0, NULL),
    ('REC1535', 'TAC18 Receivables', 'Leased to other NHS providers', '+', '£000', 0, NULL),
    ('REC1540', 'TAC18 Receivables', 'Leased to other DHSC group bodies', '+', '£000', 0, NULL),
    ('REC1250', 'TAC18 Receivables', 'Finance lease receivables at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('REC1290', 'TAC18 Receivables', 'At start of period for New FTs', '+', '£000', 0, NULL),
    ('REC1300', 'TAC18 Receivables', 'Transfers by absorption', '+', '£000', 0, NULL),
    ('REC1310', 'TAC18 Receivables', 'Additions - new finance leases of assets previously held in PPE', '+', '£000', 0, NULL),
    ('REC1311', 'TAC18 Receivables', 'Additions - new finance subleases of previously held RoU assets', '+', '£000', 0, NULL),
    ('REC1312', 'TAC18 Receivables', 'Additions - finance subleases granted simultaneously with the headlease', '+', '£000', 0, NULL),
    ('REC1320', 'TAC18 Receivables', 'Interest arising (unwinding of discount)', '+', '£000', 0, NULL),
    ('REC1330', 'TAC18 Receivables', 'Remeasurements of lease receivables - taken to I&E', '+/-', '£000', 0, NULL),
    ('REC1340', 'TAC18 Receivables', 'Remeasurements of lease receivables - arising from movements in head lease liability passed on to sublessee', '+/-', '£000', 0, NULL),
    ('REC1345', 'TAC18 Receivables', 'Movement in allowances for uncollectable lease payments (amounts arising or reversed)', '+/-', '£000', 0, NULL),
    ('REC1350', 'TAC18 Receivables', 'Lease receipts (cash payments received)', '-', '£000', 0, NULL),
    ('REC1360', 'TAC18 Receivables', 'Derecognition due to lease termination', '-', '£000', 0, NULL),
    ('REC1370', 'TAC18 Receivables', 'Transfer to FT upon authorisation', '+', '£000', 0, NULL),
    ('REC1380', 'TAC18 Receivables', 'Finance lease receivables at 31 March 2024', '+', '£000', 0, NULL),
    ('REC1260', 'TAC18 Receivables', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('REC1270', 'TAC18 Receivables', 'Finance lease receivables at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('REC1280', 'TAC18 Receivables', 'Implementation of IFRS 16 on 1 April 2022 - subleases reclassified as finance leases', '+', '£000', 0, NULL);

-- TAC19 CCE
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('CCE0010', 'TAC19 CCE', 'At 1 April', '+', '£000', 0, NULL),
    ('CCE0020', 'TAC19 CCE', 'Prior period adjustments', '+/-', '£000', 0, NULL),
    ('CCE0030', 'TAC19 CCE', 'At 1 April (restated)', '+', '£000', 0, NULL),
    ('CCE0040', 'TAC19 CCE', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('CCE0050', 'TAC19 CCE', 'Transfers by absorption', '+', '£000', 0, NULL),
    ('CCE0060', 'TAC19 CCE', 'Net change in year', '+/-', '£000', 0, NULL),
    ('CCE0070', 'TAC19 CCE', 'Transfers to FT upon authorisation', '+/-', '£000', 0, NULL),
    ('CCE0080', 'TAC19 CCE', 'At 31 March', '+', '£000', 0, NULL),
    ('CCE0090', 'TAC19 CCE', 'Cash at commercial banks and in hand', '+', '£000', 0, NULL),
    ('CCE0100', 'TAC19 CCE', 'Cash with the Government Banking Service', '+', '£000', 0, NULL),
    ('CCE0110', 'TAC19 CCE', 'Deposits with the National Loan Fund', '+', '£000', 0, NULL),
    ('CCE0120', 'TAC19 CCE', 'Other current investments', '+', '£000', 0, NULL),
    ('CCE0130', 'TAC19 CCE', 'Total cash and cash equivalents as in SoFP', '+', '£000', 1, NULL),
    ('CCE0140', 'TAC19 CCE', 'Bank overdrafts (GBS and commercial banks)', '-', '£000', 0, NULL),
    ('CCE0150', 'TAC19 CCE', 'Drawdown in committed facility (non-DHSC)', '-', '£000', 0, NULL),
    ('CCE0160', 'TAC19 CCE', 'Total cash and cash equivalents as in SoCF', '+/-', '£000', 1, NULL),
    ('CCE0170', 'TAC19 CCE', 'Bank balances', '+', '£000', 0, NULL),
    ('CCE0180', 'TAC19 CCE', 'Monies on deposit', '+', '£000', 0, NULL),
    ('CCE0190', 'TAC19 CCE', 'Total third party assets', '+', '£000', 1, NULL);

-- TAC20 Payables
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('PAY0010', 'TAC20 Payables', 'Trade payables', '+', '£000', 0, NULL),
    ('PAY0020', 'TAC20 Payables', 'Capital payables (including capital accruals)', '+', '£000', 0, NULL),
    ('PAY0030', 'TAC20 Payables', 'Accruals (revenue costs only)', '+', '£000', 0, NULL),
    ('PAY0035', 'TAC20 Payables', 'Annual leave accrual', '+', '£000', 0, NULL),
    ('PAY0040', 'TAC20 Payables', 'Receipts in advance (including payments on account)', '+', '£000', 0, NULL),
    ('PAY0041', 'TAC20 Payables', 'PFI lifecycle replacement received in advance', '+', '£000', 0, NULL),
    ('PAY0050', 'TAC20 Payables', 'Social security costs', '+', '£000', 0, NULL),
    ('PAY0060', 'TAC20 Payables', 'VAT payables', '+', '£000', 0, NULL),
    ('PAY0070', 'TAC20 Payables', 'Other taxes payable', '+', '£000', 0, NULL),
    ('PAY0080', 'TAC20 Payables', 'PDC dividend payable', '+', '£000', 0, NULL),
    ('PAY0085', 'TAC20 Payables', 'Pension contributions payable', '+', '£000', 0, NULL),
    ('PAY0110', 'TAC20 Payables', 'Other payables', '+', '£000', 0, NULL),
    ('PAY0115', 'TAC20 Payables', 'NHS charitable funds: trade and other payables', '+', '£000', 0, NULL),
    ('PAY0120', 'TAC20 Payables', 'Total current trade and other payables', '+', '£000', 1, NULL),
    ('PAY0130', 'TAC20 Payables', 'Trade payables', '+', '£000', 0, NULL),
    ('PAY0140', 'TAC20 Payables', 'Capital payables (including capital accruals)', '+', '£000', 0, NULL),
    ('PAY0150', 'TAC20 Payables', 'Accruals (revenue costs only)', '+', '£000', 0, NULL),
    ('PAY0160', 'TAC20 Payables', 'Receipts in advance (including payments on account)', '+', '£000', 0, NULL),
    ('PAY0161', 'TAC20 Payables', 'PFI lifecycle replacement received in advance', '+', '£000', 0, NULL),
    ('PAY0170', 'TAC20 Payables', 'VAT payables', '+', '£000', 0, NULL),
    ('PAY0180', 'TAC20 Payables', 'Other taxes payable', '+', '£000', 0, NULL),
    ('PAY0190', 'TAC20 Payables', 'Other payables', '+', '£000', 0, NULL),
    ('PAY0195', 'TAC20 Payables', 'NHS charitable funds: trade and other payables', '+', '£000', 0, NULL),
    ('PAY0200', 'TAC20 Payables', 'Total non-current trade and other payables', '+', '£000', 1, NULL),
    ('PAY0205', 'TAC20 Payables', 'Total trade and other payables', '+', '£000', 1, NULL),
    ('PAY0210', 'TAC20 Payables', 'Current', '+', '£000', 0, NULL),
    ('PAY0220', 'TAC20 Payables', 'Non-current', '+', '£000', 0, NULL),
    ('PAY0230', 'TAC20 Payables', '- to buy out the liability for early retirements over 5 years', '+', '£000', 0, NULL),
    ('PAY0240', 'TAC20 Payables', '- number of cases', '+', '£000', 0, NULL),
    ('PAY0340', 'TAC20 Payables', 'Deferred income: contract liability (IFRS 15)', '+', '£000', 0, NULL),
    ('PAY0345', 'TAC20 Payables', 'Deferred grants', '+', '£000', 0, NULL),
    ('PAY0350', 'TAC20 Payables', 'PFI: deferred income / credits', '+', '£000', 0, NULL),
    ('PAY0360', 'TAC20 Payables', 'Lease incentives (relating to low value / short term leases only)', '+', '£000', 0, NULL),
    ('PAY0362', 'TAC20 Payables', 'Deferred income: other (non-IFRS 15)', '+', '£000', 0, NULL),
    ('PAY0365', 'TAC20 Payables', 'NHS charitable funds: other liabilities', '+', '£000', 0, NULL),
    ('PAY0370', 'TAC20 Payables', 'Total other current liabilities', '+', '£000', 1, NULL),
    ('PAY0380', 'TAC20 Payables', 'Deferred income: contract liability (IFRS 15)', '+', '£000', 0, NULL),
    ('PAY0385', 'TAC20 Payables', 'Deferred grants', '+', '£000', 0, NULL),
    ('PAY0390', 'TAC20 Payables', 'PFI: deferred income / credits', '+', '£000', 0, NULL),
    ('PAY0400', 'TAC20 Payables', 'Lease incentives (relating to low value / short term leases only)', '+', '£000', 0, NULL),
    ('PAY0405', 'TAC20 Payables', 'Deferred income: other (non-IFRS 15)', '+', '£000', 0, NULL),
    ('PAY0415', 'TAC20 Payables', 'NHS charitable funds: other liabilities', '+', '£000', 0, NULL),
    ('PAY0410', 'TAC20 Payables', 'Net defined benefit pension scheme liability', '+', '£000', 0, NULL),
    ('PAY0420', 'TAC20 Payables', 'Total other non-current liabilities', '+', '£000', 1, NULL),
    ('PAY0425', 'TAC20 Payables', 'Total other liabilities', '+', '£000', 1, NULL),
    ('PAY0430', 'TAC20 Payables', 'Derivatives and embedded derivatives held at ''fair value through income and expenditure''', '+', '£000', 0, NULL),
    ('PAY0440', 'TAC20 Payables', 'Other financial liabilities', '+', '£000', 0, NULL),
    ('PAY0450', 'TAC20 Payables', 'Total', '+', '£000', 1, NULL),
    ('PAY0460', 'TAC20 Payables', 'Derivatives and embedded derivatives held at ''fair value through income and expenditure''', '+', '£000', 0, NULL),
    ('PAY0470', 'TAC20 Payables', 'Other financial liabilities', '+', '£000', 0, NULL),
    ('PAY0480', 'TAC20 Payables', 'Total', '+', '£000', 1, NULL);

-- TAC21 Borrowings
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('SFP0570A', 'TAC21 Borrowings', 'Bank overdrafts - Government Banking Service', '+', '£000', 0, NULL),
    ('SFP0570B', 'TAC21 Borrowings', 'Bank overdrafts - Commercial', '+', '£000', 0, NULL),
    ('BOR0010', 'TAC21 Borrowings', 'NHS charitable funds: bank overdraft', '+', '£000', 0, NULL),
    ('SFP0670C', 'TAC21 Borrowings', 'Drawdown in committed facility (non-DHSC)', '+', '£000', 0, NULL),
    ('SFP0600', 'TAC21 Borrowings', 'Capital loans', '+', '£000', 0, NULL),
    ('SFP0610', 'TAC21 Borrowings', 'Revenue support / working capital loans', '+', '£000', 0, NULL),
    ('SFP0630', 'TAC21 Borrowings', 'Other loans (non-DHSC)', '+', '£000', 0, NULL),
    ('SFP0590', 'TAC21 Borrowings', 'Lease liabilities', '+', '£000', 0, NULL),
    ('SFP0580', 'TAC21 Borrowings', 'Obligations under PFI, LIFT or other service concession contracts (excl lifecycle)', '+', '£000', 0, NULL),
    ('BOR0020', 'TAC21 Borrowings', 'NHS charitable funds: other current borrowings', '+', '£000', 0, NULL),
    ('SFP0640', 'TAC21 Borrowings', 'Total current borrowings', '+', '£000', 1, NULL),
    ('SFP0670', 'TAC21 Borrowings', 'Capital loans', '+', '£000', 0, NULL),
    ('SFP0680', 'TAC21 Borrowings', 'Revenue support / working capital loans', '+', '£000', 0, NULL),
    ('SFP0700', 'TAC21 Borrowings', 'Other loans (non-DHSC)', '+', '£000', 0, NULL),
    ('SFP0660', 'TAC21 Borrowings', 'Lease liabilities', '+', '£000', 0, NULL),
    ('SFP0650', 'TAC21 Borrowings', 'Obligations under PFI, LIFT or other service concession contracts (excl lifecycle)', '+', '£000', 0, NULL),
    ('BOR0030', 'TAC21 Borrowings', 'NHS charitable funds: other non-current borrowings', '+', '£000', 0, NULL),
    ('SFP0710', 'TAC21 Borrowings', 'Total non-current borrowings', '+', '£000', 1, NULL),
    ('BOR0302', 'TAC21 Borrowings', '- not later than one year;', '+', '£000', 0, NULL),
    ('BOR0303', 'TAC21 Borrowings', '- later than one year and not later than five years;', '+', '£000', 0, NULL),
    ('BOR0304', 'TAC21 Borrowings', '- later than five years.', '+', '£000', 0, NULL),
    ('BOR0301', 'TAC21 Borrowings', 'Total gross future lease payments', '+', '£000', 1, NULL),
    ('BOR0305', 'TAC21 Borrowings', 'Finance charges allocated to future periods', '-', '£000', 0, NULL),
    ('BOR0310', 'TAC21 Borrowings', 'Net lease liabilities', '+', '£000', 0, NULL),
    ('BOR0340', 'TAC21 Borrowings', 'Leased from other NHS providers', '+', '£000', 0, NULL),
    ('BOR0345', 'TAC21 Borrowings', 'Leased from other DHSC group bodies', '+', '£000', 0, NULL),
    ('BOR0440A', 'TAC21 Borrowings', 'Carrying value at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('BOR0470', 'TAC21 Borrowings', 'Financing cash flows - principal', '-', '£000', 0, NULL),
    ('BOR0480', 'TAC21 Borrowings', 'Financing cash flows - interest', '-', '£000', 0, NULL),
    ('BOR0490', 'TAC21 Borrowings', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('BOR0500', 'TAC21 Borrowings', 'Transfers by absorption', '+', '£000', 0, NULL),
    ('BOR0510A', 'TAC21 Borrowings', 'Lease additions (recognition of a right of use asset)', '+', '£000', 0, NULL),
    ('BOR0510B', 'TAC21 Borrowings', 'Lease additions (not recognised as RoU asset due to simultaneous sublease being created) - intra-government subleases', '+', '£000', 0, NULL),
    ('BOR0510C', 'TAC21 Borrowings', 'Lease additions (not recognised as RoU asset due to simultaneous sublease being created) - external to government subleases', '+', '£000', 0, NULL),
    ('BOR0515A', 'TAC21 Borrowings', 'Lease liability remeasurements (recognised in right of use asset)', '+/-', '£000', 0, NULL),
    ('BOR0515B', 'TAC21 Borrowings', 'Lease liability remeasurements (relating to finance subleased asset - recognised in net investment in the sublease: ie sublease receivable)', '+/-', '£000', 0, NULL),
    ('BOR0515C', 'TAC21 Borrowings', 'Lease liability remeasurements (relating to finance subleased asset - recognised in expenditure) (free text required)', '+/-', '£000', 0, NULL),
    ('BOR0530', 'TAC21 Borrowings', 'Interest charge arising in year (application of effective interest rate)', '+', '£000', 0, NULL),
    ('BOR0555', 'TAC21 Borrowings', 'Termination of lease', '-', '£000', 0, NULL),
    ('BOR0520', 'TAC21 Borrowings', 'Business combinations (not absorption transfers)', '+', '£000', 0, NULL),
    ('BOR0560', 'TAC21 Borrowings', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('BOR0565', 'TAC21 Borrowings', 'Remeasurements - retranslation gains / (losses) on foreign operations', '+/-', '£000', 0, NULL),
    ('BOR0570', 'TAC21 Borrowings', 'Other changes', '+/-', '£000', 0, NULL),
    ('BOR0580', 'TAC21 Borrowings', 'Lease liabilities as at 31 March 2024', '+', '£000', 0, NULL),
    ('BOR0450', 'TAC21 Borrowings', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('BOR0460', 'TAC21 Borrowings', 'Carrying value at 1 April 2022 - restated', '+', '£000', 0, NULL),
    ('BOR0465', 'TAC21 Borrowings', 'Impact of implementing IFRS 16 as at 1 April 2022', '+', '£000', 0, NULL),
    ('BOR0440', 'TAC21 Borrowings', 'Carrying value at 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('BOR0510', 'TAC21 Borrowings', 'Additions', '+', '£000', 0, NULL),
    ('BOR0515', 'TAC21 Borrowings', 'Lease liability remeasurements', '+/-', '£000', 0, NULL),
    ('BOR0517', 'TAC21 Borrowings', 'Remeasurement of PFI / other service concession liability resulting from change in index or rate (taken to financing costs)', '+/-', '£000', 0, NULL),
    ('BOR0540', 'TAC21 Borrowings', 'Change in effective interest rate', '+/-', '£000', 0, NULL),
    ('BOR0550', 'TAC21 Borrowings', 'Changes in fair values', '+/-', '£000', 0, NULL);

-- TAC22 Provisions
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('PRO0010', 'TAC22 Provisions', 'Pensions - Early departure costs', '+', '£000', 0, NULL),
    ('PRO0015', 'TAC22 Provisions', 'Pensions - Injury benefits', '+', '£000', 0, NULL),
    ('PRO0020', 'TAC22 Provisions', 'Legal claims', '+', '£000', 0, NULL),
    ('PRO0030', 'TAC22 Provisions', 'Restructuring', '+', '£000', 0, NULL),
    ('PRO0050', 'TAC22 Provisions', 'Equal pay (including agenda for change)', '+', '£000', 0, NULL),
    ('PRO0060', 'TAC22 Provisions', 'Redundancy', '+', '£000', 0, NULL),
    ('PRO0066', 'TAC22 Provisions', 'Capitalised lease dilapidations - cost capitalised under IFRS 16', '+', '£000', 0, NULL),
    ('PRO0016', 'TAC22 Provisions', '2019/20 clinicians'' pension reimbursement', '+', '£000', 0, NULL),
    ('PRO0070', 'TAC22 Provisions', 'Other (Includes lease dilapidations previously charged to revenue)', '+', '£000', 0, NULL),
    ('PRO0075', 'TAC22 Provisions', 'Charitable fund provisions', '+', '£000', 0, NULL),
    ('PRO0080', 'TAC22 Provisions', 'Total', '+', '£000', 1, NULL),
    ('SCI1350', 'TAC22 Provisions', 'At 1 April 2023 - brought forward', '+', '£000', 0, NULL),
    ('PRO0110', 'TAC22 Provisions', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('SCI1360', 'TAC22 Provisions', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('SCI1370', 'TAC22 Provisions', 'Change in discount rate', '+/-', '£000', 0, NULL),
    ('SCI1380', 'TAC22 Provisions', 'Arising during the year', '+', '£000', 0, NULL),
    ('SCI1380A', 'TAC22 Provisions', 'Arising during the year (relating to RoU assets derecognised under finance subleases only)', '+', '£000', 0, NULL),
    ('SCI1390A', 'TAC22 Provisions', 'Utilised during the year - accruals', '-', '£000', 0, NULL),
    ('SCI1390B', 'TAC22 Provisions', 'Utilised during the year - cash', '-', '£000', 0, NULL),
    ('SCI1395', 'TAC22 Provisions', 'Reclassified to liabilities held in disposal groups', '-', '£000', 0, NULL),
    ('SCI1399', 'TAC22 Provisions', 'Reversed unused - capital', '-', '£000', 0, NULL),
    ('SCI1400', 'TAC22 Provisions', 'Reversed unused - revenue', '-', '£000', 0, NULL),
    ('SCI1410', 'TAC22 Provisions', 'Unwinding of discount', '+/-', '£000', 0, NULL),
    ('PRO0115', 'TAC22 Provisions', 'Movement in charitable fund provisions', '+/-', '£000', 0, NULL),
    ('PRO0120', 'TAC22 Provisions', 'Transfer to FT upon authorisation', '-', '£000', 0, NULL),
    ('SCI1420', 'TAC22 Provisions', 'At 31 March 2024', '+', '£000', 0, NULL),
    ('PRO0130', 'TAC22 Provisions', '- not later than one year', '+', '£000', 0, NULL),
    ('PRO0140', 'TAC22 Provisions', '- later than one year and not later than five years', '+', '£000', 0, NULL),
    ('PRO0150', 'TAC22 Provisions', '- later than five years', '+', '£000', 0, NULL),
    ('PRO0160', 'TAC22 Provisions', 'Amount included in provisions of the NHS Resolution in respect of clinical negligence liabilities of the NHS provider', '+', '£000', 0, NULL),
    ('PRO0170', 'TAC22 Provisions', 'NHS Resolution legal claims', '-', '£000', 0, NULL),
    ('PRO0180', 'TAC22 Provisions', 'Employment tribunal and other employee related litigation', '-', '£000', 0, NULL),
    ('PRO0190', 'TAC22 Provisions', 'Redundancy', '-', '£000', 0, NULL),
    ('PRO0200', 'TAC22 Provisions', 'Other', '-', '£000', 0, NULL),
    ('PRO0210', 'TAC22 Provisions', 'Gross value of contingent liabilities', '-', '£000', 0, NULL),
    ('PRO0220', 'TAC22 Provisions', 'Amounts recoverable against liabilities', '+', '£000', 0, NULL),
    ('PRO0230', 'TAC22 Provisions', 'Net value of contingent liabilities', '-', '£000', 0, NULL),
    ('PRO0240', 'TAC22 Provisions', 'Net value of contingent assets', '+', '£000', 0, NULL);

-- TAC24 On-SoFP PFI
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('PFI0010', 'TAC24 On-SoFP PFI', 'Gross PFI, LIFT or other service concession SoFP obligation', '+', '£000', 0, NULL),
    ('PFI0020', 'TAC24 On-SoFP PFI', '- not later than one year;', '+', '£000', 0, NULL),
    ('PFI0030', 'TAC24 On-SoFP PFI', '- later than one year and not later than five years;', '+', '£000', 0, NULL),
    ('PFI0040', 'TAC24 On-SoFP PFI', '- later than five years.', '+', '£000', 0, NULL),
    ('PFI0050', 'TAC24 On-SoFP PFI', 'Finance charges allocated to future periods', '-', '£000', 0, NULL),
    ('PFI0060', 'TAC24 On-SoFP PFI', 'Net PFI, LIFT or other service concession SoFP obligation', '+', '£000', 0, NULL),
    ('PFI0070', 'TAC24 On-SoFP PFI', '- not later than one year;', '+', '£000', 0, NULL),
    ('PFI0080', 'TAC24 On-SoFP PFI', '- later than one year and not later than five years;', '+', '£000', 0, NULL),
    ('PFI0090', 'TAC24 On-SoFP PFI', '- later than five years.', '+', '£000', 0, NULL),
    ('PFI0100', 'TAC24 On-SoFP PFI', 'Total future payments committed in respect of PFI, LIFT or other service concession arrangements', '+', '£000', 1, NULL),
    ('PFI0110', 'TAC24 On-SoFP PFI', '- not later than one year;', '+', '£000', 0, NULL),
    ('PFI0120', 'TAC24 On-SoFP PFI', '- later than one year and not later than five years;', '+', '£000', 0, NULL),
    ('PFI0130', 'TAC24 On-SoFP PFI', '- later than five years.', '+', '£000', 0, NULL),
    ('CAP2530', 'TAC24 On-SoFP PFI', 'Number of schemes that the trust has (accounted for on-SoFP) as at 31 March 2024', '+', '£000', 0, NULL),
    ('CAP2660', 'TAC24 On-SoFP PFI', 'Unitary payment payable to service concession operator (total of all schemes)', '+', '£000', 0, NULL),
    ('CAP2610', 'TAC24 On-SoFP PFI', '- Interest charge', '+', '£000', 0, NULL),
    ('CAP2600', 'TAC24 On-SoFP PFI', '- Repayment of balance sheet obligation', '+', '£000', 0, NULL),
    ('CAP2590', 'TAC24 On-SoFP PFI', '- Service element (and other charges to operating expenditure excluding revenue lifecycle)', '+', '£000', 0, NULL),
    ('CAP2620', 'TAC24 On-SoFP PFI', '- Capital lifecycle maintenance', '+', '£000', 0, NULL),
    ('CAP2630', 'TAC24 On-SoFP PFI', '- Revenue lifecycle maintenance', '+', '£000', 0, NULL),
    ('CAP2640', 'TAC24 On-SoFP PFI', '- Contingent rent (should be nil in 2023/24 on an IFRS 16 basis)', '+', '£000', 0, NULL),
    ('CAP2646', 'TAC24 On-SoFP PFI', '- Addition to lifecycle prepayment - capital', '+', '£000', 0, NULL),
    ('CAP2647', 'TAC24 On-SoFP PFI', '- Addition to lifecycle prepayment - revenue', '+', '£000', 0, NULL),
    ('CAP2680', 'TAC24 On-SoFP PFI', 'Amounts charged to revenue (free text required)', '+', '£000', 0, NULL),
    ('CAP2690', 'TAC24 On-SoFP PFI', 'Amounts capitalised (free text required)', '+', '£000', 0, NULL),
    ('CAP2700', 'TAC24 On-SoFP PFI', 'Total amount paid to service concession operator', '+', '£000', 1, NULL),
    ('PFI0190', 'TAC24 On-SoFP PFI', 'PFI support income recognised in other operating income', '+', '£000', 0, NULL),
    ('PFI0300', 'TAC24 On-SoFP PFI', 'Increase in PFI / LIFT and other service concession liabilities', '-', '£000', 0, NULL),
    ('PFI0310', 'TAC24 On-SoFP PFI', 'Decrease in PDC dividend payable / increase in PDC dividend receivable', '+/-', '£000', 0, NULL),
    ('PFI0320', 'TAC24 On-SoFP PFI', 'Increase in cash and cash equivalents (impact of PDC dividend only)', '+', '£000', 0, NULL),
    ('PFI0330', 'TAC24 On-SoFP PFI', 'Impact on net assets as at 31 March 2024', '-', '£000', 0, NULL),
    ('PFI0340', 'TAC24 On-SoFP PFI', 'PFI liability remeasurement charged to finance costs', NULL, '£000', 0, NULL),
    ('PFI0350', 'TAC24 On-SoFP PFI', 'Increase in interest arising on PFI liability', '-', '£000', 0, NULL),
    ('PFI0360', 'TAC24 On-SoFP PFI', 'Reduction in contingent rent (including amounts recognised in service costs)', '+', '£000', 0, NULL),
    ('PFI0370', 'TAC24 On-SoFP PFI', 'Reduction in PDC dividend charge', '+', '£000', 0, NULL),
    ('PFI0380', 'TAC24 On-SoFP PFI', 'Net impact on surplus / (deficit)', '+/-', '£000', 0, NULL),
    ('PFI0390', 'TAC24 On-SoFP PFI', 'Adjustment to reserves for the cumulative retrospective impact on 1 April 2023', NULL, '£000', 0, NULL),
    ('PFI0400', 'TAC24 On-SoFP PFI', 'Net impact on 2023/24 surplus / deficit', '+/-', '£000', 0, NULL),
    ('PFI0410', 'TAC24 On-SoFP PFI', 'Impact on equity as at 31 March 2024', '+/-', '£000', 0, NULL),
    ('PFI0420', 'TAC24 On-SoFP PFI', 'Increase in cash outflows for capital element of PFI / LIFT', '-', '£000', 0, NULL),
    ('PFI0430', 'TAC24 On-SoFP PFI', 'Decrease in cash outflows for financing element of PFI / LIFT (including amounts recorded in service costs)', '+', '£000', 0, NULL),
    ('PFI0440', 'TAC24 On-SoFP PFI', 'Decrease in cash outflows for PDC dividend', '+', '£000', 0, NULL),
    ('PFI0450', 'TAC24 On-SoFP PFI', 'Net impact on cash flows from financing activities', '+', '£000', 0, NULL);

-- TAC25 Off-SoFP PFI
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('PFI1000', 'TAC25 Off-SoFP PFI', '- not later than one year;', '+', '£000', 0, NULL),
    ('PFI1010', 'TAC25 Off-SoFP PFI', '- later than one year and not later than five years;', '+', '£000', 0, NULL),
    ('PFI1020', 'TAC25 Off-SoFP PFI', '- later than five years.', '+', '£000', 0, NULL),
    ('PFI1030', 'TAC25 Off-SoFP PFI', 'Total', '+', '£000', 1, NULL),
    ('PFI1040', 'TAC25 Off-SoFP PFI', 'Total charge to operating expenditure for off-SoFP schemes', '+', '£000', 1, NULL),
    ('PFI1050', 'TAC25 Off-SoFP PFI', 'Number of schemes that the trust has (accounted for off-SoFP) as at 31 March 2024', '+', '£000', 0, NULL);

-- TAC26 Pension
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('PEN0010', 'TAC26 Pension', 'Present value of the defined benefit obligation at 1 April', '-', '£000', 0, NULL),
    ('PEN0020', 'TAC26 Pension', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('PEN0030', 'TAC26 Pension', 'Present value of the defined benefit obligation at 1 April', '-', '£000', 0, NULL),
    ('PEN0040', 'TAC26 Pension', 'At start of period for new FTs', '-', '£000', 0, NULL),
    ('PEN0050', 'TAC26 Pension', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('PEN0060', 'TAC26 Pension', 'Current service cost', '-', '£000', 0, NULL),
    ('PEN0070', 'TAC26 Pension', 'Interest cost', '-', '£000', 0, NULL),
    ('PEN0080', 'TAC26 Pension', 'Contribution by plan participants', '-', '£000', 0, NULL),
    ('PEN0090', 'TAC26 Pension', '- Actuarial gains/(losses)', '+/-', '£000', 0, NULL),
    ('PEN0100', 'TAC26 Pension', 'Benefits paid', '+', '£000', 0, NULL),
    ('PEN0110', 'TAC26 Pension', 'Past service costs', NULL, '£000', 0, NULL),
    ('PEN0120', 'TAC26 Pension', 'Business combinations (transfers in/out)', '+/-', '£000', 0, NULL),
    ('PEN0130', 'TAC26 Pension', 'Curtailments and settlements', '+', '£000', 0, NULL),
    ('PEN0140', 'TAC26 Pension', 'Transferred to NHS foundation trust upon authorisation as FT', '+', '£000', 0, NULL),
    ('PEN0150', 'TAC26 Pension', 'Present value of the defined benefit obligation at 31 March', '-', '£000', 0, NULL),
    ('PEN0160', 'TAC26 Pension', 'Plan assets at fair value at 1 April', '+', '£000', 0, NULL),
    ('PEN0170', 'TAC26 Pension', 'Prior period adjustment', '+/-', '£000', 0, NULL),
    ('PEN0180', 'TAC26 Pension', 'Present value of plan assets at 1 April', '+', '£000', 0, NULL),
    ('PEN0190', 'TAC26 Pension', 'At start of period for new FTs', '+', '£000', 0, NULL),
    ('PEN0200', 'TAC26 Pension', 'Transfers by absorption', '+/-', '£000', 0, NULL),
    ('PEN0210', 'TAC26 Pension', 'Interest income', '+', '£000', 0, NULL),
    ('PEN0220', 'TAC26 Pension', '- Return on plan assets (excludes any amounts already included in interest income above)', '+', '£000', 0, NULL),
    ('PEN0230', 'TAC26 Pension', '- Actuarial gains/(losses)', '+/-', '£000', 0, NULL),
    ('PEN0240', 'TAC26 Pension', '- Changes in the effect of limiting a net defined benefit asset to the asset ceiling (excluding amounts included in interest income/expense)', '+/-', '£000', 0, NULL),
    ('PEN0250', 'TAC26 Pension', 'Contributions by the employer', '+', '£000', 0, NULL),
    ('PEN0260', 'TAC26 Pension', 'Contributions by the plan participants', '+', '£000', 0, NULL),
    ('PEN0270', 'TAC26 Pension', 'Benefits paid', '-', '£000', 0, NULL),
    ('PEN0280', 'TAC26 Pension', 'Business combinations (transfers in/out)', '+/-', '£000', 0, NULL),
    ('PEN0290', 'TAC26 Pension', 'Settlements', '-', '£000', 0, NULL),
    ('PEN0300', 'TAC26 Pension', 'Transferred to NHS foundation trust upon authorisation as FT', '-', '£000', 0, NULL),
    ('PEN0310', 'TAC26 Pension', 'Plan assets at fair value at 31 March', '+', '£000', 0, NULL),
    ('PEN0320', 'TAC26 Pension', 'Plan surplus/(deficit) at 31 March', '+/-', '£000', 0, NULL),
    ('PEN0330', 'TAC26 Pension', 'Present value of the defined benefit obligation', '-', '£000', 0, NULL),
    ('PEN0340', 'TAC26 Pension', 'Plan assets at fair value', '+', '£000', 0, NULL),
    ('PEN0370', 'TAC26 Pension', 'Net defined benefit (obligation)/asset recognised in the SoFP at 31 March', '+/-', '£000', 0, NULL),
    ('PEN0372', 'TAC26 Pension', 'Fair value of any reimbursement right recognised as a separate asset on the SoFP', '+', '£000', 0, NULL),
    ('PEN0375', 'TAC26 Pension', 'Total net (liability)/asset after the impact of reimbursement rights as at 31 March', NULL, '£000', 1, NULL),
    ('PEN0380', 'TAC26 Pension', 'Current service cost', '+/-', '£000', 0, NULL),
    ('PEN0390', 'TAC26 Pension', 'Interest expense / income', '+/-', '£000', 0, NULL),
    ('PEN0400', 'TAC26 Pension', 'Past service cost', '+/-', '£000', 0, NULL),
    ('PEN0410', 'TAC26 Pension', 'Gains / (losses) on curtailment and settlement', '+/-', '£000', 0, NULL),
    ('PEN0420', 'TAC26 Pension', 'Total net (charge)/gain recognised in SoCI', NULL, '£000', 1, NULL);

-- TAC27 Fin Inst
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('FI0020', 'TAC27 Fin Inst', 'Receivables (excluding non financial assets) - with DHSC group bodies', '+', '£000', 0, NULL),
    ('FI0030', 'TAC27 Fin Inst', 'Receivables (excluding non financial assets) - with other bodies', '+', '£000', 0, NULL),
    ('FI0040', 'TAC27 Fin Inst', 'Other investments / financial assets', '+', '£000', 0, NULL),
    ('FI0050', 'TAC27 Fin Inst', 'Cash and cash equivalents', '+', '£000', 0, NULL),
    ('FI0055', 'TAC27 Fin Inst', 'Consolidated NHS Charitable fund financial assets', '+', '£000', 0, NULL),
    ('FI0060', 'TAC27 Fin Inst', 'Total as at 31 March 2024', '+', '£000', 1, NULL),
    ('FI0081', 'TAC27 Fin Inst', 'DHSC loans', '+', '£000', 0, NULL),
    ('FI0082', 'TAC27 Fin Inst', 'Other borrowings excluding lease and PFI liabilities', '+', '£000', 0, NULL),
    ('FI0090', 'TAC27 Fin Inst', 'Obligations under leases', '+', '£000', 0, NULL),
    ('FI0100', 'TAC27 Fin Inst', 'Obligations under PFI, LIFT and other service concession contracts', '+', '£000', 0, NULL),
    ('FI0110', 'TAC27 Fin Inst', 'Trade and other payables (excluding non financial liabilities) - with DHSC group bodies', '+', '£000', 0, NULL),
    ('FI0120', 'TAC27 Fin Inst', 'Trade and other payables (excluding non financial liabilities) - with other bodies', '+', '£000', 0, NULL),
    ('FI0130', 'TAC27 Fin Inst', 'Other financial liabilities', '+', '£000', 0, NULL),
    ('FI0140', 'TAC27 Fin Inst', 'IAS 37 provisions which are financial liabilities', '+', '£000', 0, NULL),
    ('FI0145', 'TAC27 Fin Inst', 'Consolidated NHS charitable fund financial liabilities', '+', '£000', 0, NULL),
    ('FI0150', 'TAC27 Fin Inst', 'Total as at 31 March 2024', '+', '£000', 1, NULL),
    ('FI0160', 'TAC27 Fin Inst', 'In one year or less', '+', '£000', 0, NULL),
    ('FI0170', 'TAC27 Fin Inst', 'In more than one year but not more than five years', '+', '£000', 0, NULL),
    ('FI0190', 'TAC27 Fin Inst', 'In more than five years', '+', '£000', 0, NULL),
    ('FI0200', 'TAC27 Fin Inst', 'Total financial liabilities', '+', '£000', 1, NULL),
    ('FI0220', 'TAC27 Fin Inst', 'Receivables (excluding non financial assets) - with NHS and DHSC bodies', '+', '£000', 0, NULL),
    ('FI0230', 'TAC27 Fin Inst', 'Receivables (excluding non financial assets) - with other bodies', '+', '£000', 0, NULL),
    ('FI0240', 'TAC27 Fin Inst', 'Other investments / financial assets', '+', '£000', 0, NULL),
    ('FI0250', 'TAC27 Fin Inst', 'Cash and cash equivalents', '+', '£000', 0, NULL),
    ('FI0255', 'TAC27 Fin Inst', 'Consolidated NHS Charitable fund financial assets', '+', '£000', 0, NULL),
    ('FI0260', 'TAC27 Fin Inst', 'Total assets', '+', '£000', 1, NULL),
    ('FI0275', 'TAC27 Fin Inst', 'DHSC loans', '+', '£000', 0, NULL),
    ('FI0280', 'TAC27 Fin Inst', 'Other borrowings excluding lease and PFI liabilities', '+', '£000', 0, NULL),
    ('FI0290', 'TAC27 Fin Inst', 'Obligations under leases', '+', '£000', 0, NULL),
    ('FI0300', 'TAC27 Fin Inst', 'Obligations under PFI, LIFT and other service concession contracts', '+', '£000', 0, NULL),
    ('FI0310', 'TAC27 Fin Inst', 'Trade and other payables (excluding non financial liabilities) - with NHS and DHSC bodies', '+', '£000', 0, NULL),
    ('FI0320', 'TAC27 Fin Inst', 'Trade and other payables (excluding non financial liabilities) - with other bodies', '+', '£000', 0, NULL),
    ('FI0330', 'TAC27 Fin Inst', 'Other financial liabilities', '+', '£000', 0, NULL),
    ('FI0340', 'TAC27 Fin Inst', 'IAS 37 provisions which are financial liabilities', '+', '£000', 0, NULL),
    ('FI0345', 'TAC27 Fin Inst', 'Consolidated NHS charitable fund financial liabilities', '+', '£000', 0, NULL),
    ('FI0350', 'TAC27 Fin Inst', 'Total liabilities', '+', '£000', 1, NULL);

-- TAC28 Disclosures
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('OTD0010', 'TAC28 Disclosures', 'Property, plant and equipment', '+', '£000', 0, NULL),
    ('OTD0020', 'TAC28 Disclosures', 'Intangible assets', '+', '£000', 0, NULL),
    ('OTD0030', 'TAC28 Disclosures', 'Total', '+', '£000', 1, NULL),
    ('OTD0031', 'TAC28 Disclosures', 'Commitments for leases not yet commenced to which the Trust is contractually committed', '+', '£000', 0, NULL),
    ('OTD0032', 'TAC28 Disclosures', 'Variable lease payments (not dependent on an index or rate)', '+', '£000', 0, NULL),
    ('OTD0033', 'TAC28 Disclosures', 'Extension options and termination options (not reasonably certain to be exercised)', '+', '£000', 0, NULL),
    ('OTD0034', 'TAC28 Disclosures', 'Residual value guarantees', '+', '£000', 0, NULL),
    ('OTD0035', 'TAC28 Disclosures', 'Other (unlocked on request)', '+', '£000', 0, NULL),
    ('OTD0039', 'TAC28 Disclosures', 'Total', '+', '£000', 1, NULL),
    ('OTD0040', 'TAC28 Disclosures', 'not later than 1 year', '+', '£000', 0, NULL),
    ('OTD0050', 'TAC28 Disclosures', 'after 1 year and not later than 5 years', '+', '£000', 0, NULL),
    ('OTD0060', 'TAC28 Disclosures', 'paid thereafter', '+', '£000', 0, NULL),
    ('OTD0070', 'TAC28 Disclosures', 'Total', '+', '£000', 1, NULL),
    ('OTD0080', 'TAC28 Disclosures', 'Value of transactions directly with board members (excluding salaries)', '+', '£000', 0, NULL),
    ('OTD0090', 'TAC28 Disclosures', 'Value of transactions directly with key staff members (excluding salaries)', '+', '£000', 0, NULL),
    ('OTD0100', 'TAC28 Disclosures', 'Charitable funds (where not consolidated)', '+', '£000', 0, NULL),
    ('OTD0110', 'TAC28 Disclosures', 'Non-consolidated subsidiaries and associates / joint ventures', '+', '£000', 0, NULL),
    ('OTD0120', 'TAC28 Disclosures', 'Other bodies or persons outside of the whole of government accounting boundary', '+', '£000', 0, NULL),
    ('OTD0130', 'TAC28 Disclosures', 'Total value of transactions with related parties', '+', '£000', 1, NULL),
    ('OTD0140', 'TAC28 Disclosures', 'Value of balances directly with board members (excluding salaries)', '+', '£000', 0, NULL),
    ('OTD0150', 'TAC28 Disclosures', 'Value of balances directly with key staff members (excluding salaries)', '+', '£000', 0, NULL),
    ('OTD0160', 'TAC28 Disclosures', 'Charitable funds (where not consolidated)', '+', '£000', 0, NULL),
    ('OTD0170', 'TAC28 Disclosures', 'Non-consolidated subsidiaries and associates / joint ventures', '+', '£000', 0, NULL),
    ('OTD0180', 'TAC28 Disclosures', 'Other bodies or persons outside of the whole of government accounting boundary', '+', '£000', 0, NULL),
    ('OTD0190', 'TAC28 Disclosures', 'Value of credit loss allowances held against related parties (excludes salaries)', '-', '£000', 0, NULL),
    ('OTD0210', 'TAC28 Disclosures', 'Total balances with related parties', '+', '£000', 1, NULL),
    ('OTD0200', 'TAC28 Disclosures', 'Value of balances with related parties written off in year (excludes salaries)', '-', '£000', 0, NULL),
    ('OTD0230', 'TAC28 Disclosures', 'Adjusted financial performance surplus/(deficit) (control total basis)', '+/-', '£000', 0, NULL),
    ('OTD0240', 'TAC28 Disclosures', 'Remove impairments scoring to Departmental Expenditure Limit', '+/-', '£000', 0, NULL),
    ('OTD0250', 'TAC28 Disclosures', 'Add back income for impact of 2022/23 post-accounts PSF reallocation', '+', '£000', 0, NULL),
    ('OTD0255', 'TAC28 Disclosures', 'Add back non-cash element of On-SoFP pension scheme charges', NULL, '£000', 0, NULL),
    ('OTD0256', 'TAC28 Disclosures', 'Remove PPA adjustment', '+/-', '£000', 0, NULL),
    ('OTD0257', 'TAC28 Disclosures', 'Add back incremental impact of IFRS 16 on PFI revenue costs in 2023/24', '+/-', '£000', 0, NULL),
    ('OTD0260', 'TAC28 Disclosures', 'IFRIC 12 breakeven adjustment', '+', '£000', 0, NULL),
    ('OTD0270', 'TAC28 Disclosures', 'Breakeven duty financial performance surplus/(deficit)', '+/-', '£000', 0, NULL),
    ('OTD0280', 'TAC28 Disclosures', 'Breakeven duty in-year financial performance', '+/-', '£000', 0, NULL),
    ('OTD0290', 'TAC28 Disclosures', 'Breakeven duty cumulative position', '+/-', '£000', 0, NULL),
    ('OTD0300', 'TAC28 Disclosures', 'Operating income (excluding consolidated charitable funds)', '+', '£000', 0, NULL),
    ('OTD0310', 'TAC28 Disclosures', 'Cumulative breakeven position as a percentage of operating income', NULL, '£000', 0, NULL),
    ('OTD0330', 'TAC28 Disclosures', 'Property, Plant and Equipment', '+', '£000', 0, NULL),
    ('OTD0340', 'TAC28 Disclosures', 'Intangible assets', '+', '£000', 0, NULL),
    ('OTD0350', 'TAC28 Disclosures', 'Investment property', '+', '£000', 0, NULL),
    ('OTD0360', 'TAC28 Disclosures', 'Right of use assets', '+', '£000', 0, NULL),
    ('OTD0370', 'TAC28 Disclosures', 'Total gross capital expenditure', '+', '£000', 1, NULL),
    ('OTD0380', 'TAC28 Disclosures', 'Property, Plant and Equipment', '-', '£000', 0, NULL),
    ('OTD0390', 'TAC28 Disclosures', 'Intangible assets', '-', '£000', 0, NULL),
    ('OTD0400', 'TAC28 Disclosures', 'Investment property', '-', '£000', 0, NULL),
    ('OTD0410', 'TAC28 Disclosures', 'Right of use assets', '-', '£000', 0, NULL),
    ('OTD0420', 'TAC28 Disclosures', 'Total disposals', '-', '£000', 1, NULL),
    ('OTD0430', 'TAC28 Disclosures', 'Less: Donated, granted and peppercorn lease additions', '-', '£000', 0, NULL),
    ('OTD0440', 'TAC28 Disclosures', 'Plus: Loss on disposal of peppercorn leased assets', '+', '£000', 0, NULL),
    ('OTD0445', 'TAC28 Disclosures', 'Plus: Loss on disposal for capital grants in kind', '+', '£000', 0, NULL),
    ('OTD0450', 'TAC28 Disclosures', 'Charge against Capital Resource Limit', '+/-', '£000', 0, NULL),
    ('OTD0460', 'TAC28 Disclosures', 'Capital Resource Limit', '+', '£000', 0, NULL),
    ('OTD0470', 'TAC28 Disclosures', 'Under / (over) spend against CRL', '+/-', '£000', 0, NULL);

-- TAC29 Losses+SP
INSERT INTO dim_subcode (sub_code, worksheet_name, description, expected_sign, unit, is_subtotal, analytics_category) VALUES
    ('LSP0010', 'TAC29 Losses+SP', 'a. theft, fraud etc', '+', '£000', 0, NULL),
    ('LSP0020', 'TAC29 Losses+SP', 'b. overpayment of salaries etc.', '+', '£000', 0, NULL),
    ('LSP0030', 'TAC29 Losses+SP', 'c. other causes', '+', '£000', 0, NULL),
    ('LSP0040', 'TAC29 Losses+SP', '2. Fruitless payments and constructive losses', '+', '£000', 0, NULL),
    ('LSP0050', 'TAC29 Losses+SP', 'a. private patients', '+', '£000', 0, NULL),
    ('LSP0060', 'TAC29 Losses+SP', 'b. overseas visitors', '+', '£000', 0, NULL),
    ('LSP0070', 'TAC29 Losses+SP', 'c. other', '+', '£000', 0, NULL),
    ('LSP0080', 'TAC29 Losses+SP', 'a. theft, fraud etc', '+', '£000', 0, NULL),
    ('LSP0090', 'TAC29 Losses+SP', 'b. stores losses', '+', '£000', 0, NULL),
    ('LSP0100', 'TAC29 Losses+SP', 'c. other', '+', '£000', 0, NULL),
    ('LSP0110', 'TAC29 Losses+SP', 'Total losses', '+', '£000', 1, NULL),
    ('LSP0120', 'TAC29 Losses+SP', '5. Compensation under court order or legally binding arbitration award', '+', '£000', 0, NULL),
    ('LSP0130', 'TAC29 Losses+SP', '6. Extra contractual to contractors', '+', '£000', 0, NULL),
    ('LSP0140', 'TAC29 Losses+SP', 'a. loss of personal effects', '+', '£000', 0, NULL),
    ('LSP0150', 'TAC29 Losses+SP', 'b. clinical negligence with advice', '+', '£000', 0, NULL),
    ('LSP0160', 'TAC29 Losses+SP', 'c. personal injury with advice', '+', '£000', 0, NULL),
    ('LSP0170', 'TAC29 Losses+SP', 'd. other negligence and injury', '+', '£000', 0, NULL),
    ('LSP0180', 'TAC29 Losses+SP', 'e. other employment payments (should not include special severance payments which are disclosed below)', '+', '£000', 0, NULL),
    ('LSP0190', 'TAC29 Losses+SP', 'f. patient referrals outside the UK and EEA Guidelines', '+', '£000', 0, NULL),
    ('LSP0200', 'TAC29 Losses+SP', 'g. other', '+', '£000', 0, NULL),
    ('LSP0210', 'TAC29 Losses+SP', 'h. maladministration, no financial loss', '+', '£000', 0, NULL),
    ('LSP0220', 'TAC29 Losses+SP', '8. Special severance payments', '+', '£000', 0, NULL),
    ('LSP0230', 'TAC29 Losses+SP', '9. Extra statutory and regulatory', '+', '£000', 0, NULL),
    ('LSP0240', 'TAC29 Losses+SP', 'Total special payments', '+', '£000', 1, NULL),
    ('LSP0250', 'TAC29 Losses+SP', 'Total losses and special payments', '+', '£000', 1, NULL),
    ('LSP0260', 'TAC29 Losses+SP', '1. Losses of cash (including cases of fraud)', '+', '£000', 0, NULL),
    ('LSP0270', 'TAC29 Losses+SP', '2. Fruitless payments and constructive losses', '+', '£000', 0, NULL),
    ('LSP0280', 'TAC29 Losses+SP', '3. Bad debts and claims abandoned', '+', '£000', 0, NULL),
    ('LSP0290', 'TAC29 Losses+SP', '4. Damage to buildings, property etc.', '+', '£000', 0, NULL),
    ('LSP0301', 'TAC29 Losses+SP', '5. Compensation under legal obligation', '+', '£000', 0, NULL),
    ('LSP0311', 'TAC29 Losses+SP', '6. Extra contractual to contractors', '+', '£000', 0, NULL),
    ('LSP0321', 'TAC29 Losses+SP', '7. Ex gratia payments', '+', '£000', 0, NULL),
    ('LSP0331', 'TAC29 Losses+SP', '8. Special severance payments', '+', '£000', 0, NULL),
    ('LSP0341', 'TAC29 Losses+SP', '9. Extra statutory and regulatory', '+', '£000', 0, NULL),
    ('LSP0360', 'TAC29 Losses+SP', 'TOTAL GIFTS', '+', '£000', 1, NULL),
    ('LSP0370', 'TAC29 Losses+SP', 'Gift 1', '+', '£000', 0, NULL),
    ('LSP0380', 'TAC29 Losses+SP', 'Gift 2', '+', '£000', 0, NULL),
    ('LSP0390', 'TAC29 Losses+SP', 'Gift 3', '+', '£000', 0, NULL),
    ('LSP0400', 'TAC29 Losses+SP', 'Gift 4', '+', '£000', 0, NULL),
    ('LSP0410', 'TAC29 Losses+SP', 'Gift 5', '+', '£000', 0, NULL);


-- ============================================================
-- SILVER — FACT TABLE
-- ============================================================

USE nhs_silver;

DROP TABLE IF EXISTS fct_tac;
CREATE TABLE fct_tac (
    tac_id              BIGINT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    org_code            CHAR(3)         NOT NULL,
    financial_year      CHAR(7)         NOT NULL,
    worksheet_name      VARCHAR(50)     NOT NULL,
    table_id            SMALLINT        NOT NULL,
    main_code           VARCHAR(20)     NOT NULL,
    sub_code            VARCHAR(20)     NOT NULL,
    total_000s          DECIMAL(14,0)   NOT NULL,
    trust_type          VARCHAR(20)     NOT NULL,
    source_file         VARCHAR(200)    NOT NULL,
    load_ts             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_tac (org_code, financial_year, main_code, sub_code),
    INDEX idx_fct_org_year  (org_code, financial_year),
    INDEX idx_fct_sub_code  (sub_code),
    INDEX idx_fct_worksheet (worksheet_name),
    INDEX idx_fct_year      (financial_year),
    FOREIGN KEY (org_code)       REFERENCES dim_trust(org_code),
    FOREIGN KEY (financial_year) REFERENCES dim_financial_year(financial_year),
    FOREIGN KEY (worksheet_name) REFERENCES dim_worksheet(worksheet_name)
) ENGINE=InnoDB;


-- ============================================================
-- GOLD — ANALYTICAL VIEWS
-- ============================================================

USE nhs_gold;

-- v_income_expenditure: top-level I&E from TAC02 SoCI
DROP VIEW IF EXISTS v_income_expenditure;
CREATE VIEW v_income_expenditure AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,
    MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END) AS patient_care_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END) AS other_income_000s,
    COALESCE(MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END), 0)
        + COALESCE(MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END), 0)
        AS total_income_000s,
    ABS(COALESCE(MAX(CASE WHEN f.sub_code = 'SCI0125A' THEN f.total_000s END), 0)) AS total_expenditure_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s END) AS operating_surplus_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240'  THEN f.total_000s END) AS net_surplus_000s
FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC02 SoCI'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;

-- v_expenditure_breakdown: operating expenditure by category
DROP VIEW IF EXISTS v_expenditure_breakdown;
CREATE VIEW v_expenditure_breakdown AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,
    SUM(CASE WHEN sc.analytics_category = 'PAY'                 THEN f.total_000s ELSE 0 END) AS pay_000s,
    SUM(CASE WHEN sc.analytics_category = 'NON_PAY'             THEN f.total_000s ELSE 0 END) AS non_pay_000s,
    SUM(CASE WHEN sc.analytics_category = 'NON_PAY_EXCL_EBITDA' THEN f.total_000s ELSE 0 END) AS depreciation_amort_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0170' THEN f.total_000s END) AS drugs_cost_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0130' THEN f.total_000s END) AS staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0390' THEN f.total_000s END) AS total_expenditure_000s
FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t    ON f.org_code = t.org_code
JOIN nhs_silver.dim_subcode sc ON f.sub_code = sc.sub_code
WHERE f.worksheet_name = 'TAC08 Op Exp'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;

-- v_workforce: staff costs and WTE from TAC09
DROP VIEW IF EXISTS v_workforce;
CREATE VIEW v_workforce AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,
    MAX(CASE WHEN f.sub_code = 'STA0250' THEN f.total_000s END) AS total_staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'STA0220' THEN f.total_000s END) AS gross_staff_cost_000s,
    MAX(CASE WHEN f.sub_code = 'STA0410' THEN f.total_000s END) AS total_wte,
    MAX(CASE WHEN f.sub_code = 'STA0310' THEN f.total_000s END) AS medical_wte,
    MAX(CASE WHEN f.sub_code = 'STA0350' THEN f.total_000s END) AS nursing_wte,
    MAX(CASE WHEN f.sub_code = 'STA0330' THEN f.total_000s END) AS admin_estates_wte,
    MAX(CASE WHEN f.sub_code = 'STA0370' THEN f.total_000s END) AS scientific_tech_wte,
    MAX(CASE WHEN f.sub_code = 'STA0550' THEN f.total_000s END) AS avg_days_lost_per_wte
FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC09 Staff'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;

-- v_kpis: computed KPIs
DROP VIEW IF EXISTS v_kpis;
CREATE VIEW v_kpis AS
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
    ex.pay_000s,
    ex.staff_cost_000s,
    ex.drugs_cost_000s,
    ex.depreciation_amort_000s,
    wf.total_wte,
    wf.medical_wte,
    wf.nursing_wte,
    wf.avg_days_lost_per_wte,
    -- EBITDA
    ie.operating_surplus_000s + COALESCE(ex.depreciation_amort_000s, 0) AS ebitda_000s,
    -- EBITDA Margin %
    ROUND(
        (ie.operating_surplus_000s + COALESCE(ex.depreciation_amort_000s, 0))
        / NULLIF(ie.total_income_000s, 0) * 100, 1
    ) AS ebitda_margin_pct,
    -- Pay as % of income
    ROUND(ex.pay_000s / NULLIF(ie.total_income_000s, 0) * 100, 1) AS pay_pct_income,
    -- Cost per WTE (£000s per WTE)
    ROUND(ex.staff_cost_000s / NULLIF(wf.total_wte, 0), 1) AS cost_per_wte_000s,
    -- Net surplus margin %
    ROUND(ie.net_surplus_000s / NULLIF(ie.total_income_000s, 0) * 100, 1) AS net_surplus_margin_pct
FROM v_income_expenditure ie
LEFT JOIN v_expenditure_breakdown ex
    ON ie.org_code = ex.org_code AND ie.financial_year = ex.financial_year
LEFT JOIN v_workforce wf
    ON ie.org_code = wf.org_code AND ie.financial_year = wf.financial_year;

-- v_trust_annual_scorecard: one-row-per-trust-per-year wide table combining v_kpis/v_income_expenditure/v_expenditure_breakdown/v_workforce
DROP VIEW IF EXISTS v_trust_annual_scorecard;
CREATE VIEW v_trust_annual_scorecard AS
SELECT
    k.org_code,
    k.organisation_name,
    k.sector,
    k.region,
    k.trust_type,
    k.financial_year,

    k.total_income_000s,
    ie.patient_care_income_000s,
    ie.other_income_000s,

    MAX(CASE WHEN f.sub_code = 'INC0197' THEN f.total_000s END) AS api_variable_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0198' THEN f.total_000s END) AS api_fixed_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0200' THEN f.total_000s END) AS high_cost_drugs_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0330' THEN f.total_000s END) AS private_patient_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC0350' THEN f.total_000s END) AS total_patient_income_tac06_000s,

    MAX(CASE WHEN f.sub_code = 'INC1230A' THEN f.total_000s END) AS rd_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC1240A' THEN f.total_000s END) AS education_training_income_000s,
    MAX(CASE WHEN f.sub_code = 'INC1360'  THEN f.total_000s END) AS total_other_income_tac07_000s,

    k.total_expenditure_000s,
    k.pay_000s,
    ex.non_pay_000s,
    ex.depreciation_amort_000s,
    k.drugs_cost_000s,
    ex.staff_cost_000s,

    MAX(CASE WHEN f.sub_code = 'EXP0150' THEN f.total_000s END) AS clinical_supplies_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0160' THEN f.total_000s END) AS general_supplies_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0290A' THEN f.total_000s END) AS clinical_negligence_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0240'  THEN f.total_000s END) AS depreciation_000s,
    MAX(CASE WHEN f.sub_code = 'EXP0250'  THEN f.total_000s END) AS amortisation_000s,

    k.operating_surplus_000s,
    k.net_surplus_000s,
    k.ebitda_000s,

    MAX(CASE WHEN f.sub_code = 'SCI0150' THEN f.total_000s END) AS finance_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0160' THEN f.total_000s END) AS finance_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0170' THEN f.total_000s END) AS pdc_dividend_000s,

    wf.total_wte,
    wf.total_staff_cost_000s,
    wf.gross_staff_cost_000s,

    k.ebitda_margin_pct,
    k.pay_pct_income,
    k.cost_per_wte_000s,
    k.net_surplus_margin_pct,

    CASE WHEN k.operating_surplus_000s < 0 THEN 1 ELSE 0 END AS is_deficit,
    CASE WHEN k.ebitda_margin_pct < 2 THEN 'Red'
         WHEN k.ebitda_margin_pct < 5 THEN 'Amber'
         ELSE 'Green' END AS ebitda_rag,
    CASE WHEN k.net_surplus_000s < 0 THEN 'Red'
         WHEN k.net_surplus_000s = 0 THEN 'Amber'
         ELSE 'Green' END AS surplus_rag

FROM v_kpis k
JOIN v_income_expenditure ie
    ON k.org_code = ie.org_code AND k.financial_year = ie.financial_year
LEFT JOIN v_expenditure_breakdown ex
    ON k.org_code = ex.org_code AND k.financial_year = ex.financial_year
LEFT JOIN v_workforce wf
    ON k.org_code = wf.org_code AND k.financial_year = wf.financial_year
LEFT JOIN nhs_silver.fct_tac f
    ON k.org_code = f.org_code AND k.financial_year = f.financial_year
    AND f.sub_code IN (
        'INC0197','INC0198','INC0200','INC0330','INC0350',
        'INC1230A','INC1240A','INC1360',
        'EXP0150','EXP0160','EXP0290A','EXP0240','EXP0250',
        'SCI0150','SCI0160','SCI0170'
    )
WHERE k.total_income_000s > 0
GROUP BY
    k.org_code, k.organisation_name, k.sector, k.region, k.trust_type,
    k.financial_year, k.total_income_000s, ie.patient_care_income_000s,
    ie.other_income_000s, k.total_expenditure_000s, k.pay_000s,
    ex.non_pay_000s, ex.depreciation_amort_000s, k.drugs_cost_000s,
    ex.staff_cost_000s, k.operating_surplus_000s, k.net_surplus_000s,
    k.ebitda_000s, wf.total_wte, wf.total_staff_cost_000s,
    wf.gross_staff_cost_000s, k.ebitda_margin_pct, k.pay_pct_income,
    k.cost_per_wte_000s, k.net_surplus_margin_pct;

-- v_profit_and_loss: full statutory Profit & Loss from TAC02 SoCI/SOC, all real lines
-- (excludes SOC0200-SOC0250, a memo note on surplus attribution between non-controlling
-- interest and owners of the parent that is not part of the primary statement and is blank
-- for the great majority of single-entity NHS trusts)
DROP VIEW IF EXISTS v_profit_and_loss;
CREATE VIEW v_profit_and_loss AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,

    -- Operating result
    MAX(CASE WHEN f.sub_code = 'SCI0100A' THEN f.total_000s END) AS patient_care_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0110A' THEN f.total_000s END) AS other_operating_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0125A' THEN f.total_000s END) AS operating_expenses_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0140A' THEN f.total_000s END) AS operating_surplus_000s,

    -- Finance costs
    MAX(CASE WHEN f.sub_code = 'SCI0150'  THEN f.total_000s END) AS finance_income_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0160'  THEN f.total_000s END) AS finance_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0170'  THEN f.total_000s END) AS pdc_dividend_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0180'  THEN f.total_000s END) AS net_finance_costs_000s,

    -- Other items down to the bottom line
    MAX(CASE WHEN f.sub_code = 'SCI0190A' THEN f.total_000s END) AS other_gains_losses_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0200'  THEN f.total_000s END) AS share_of_associates_jv_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0210'  THEN f.total_000s END) AS gains_losses_transfers_absorption_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0230'  THEN f.total_000s END) AS corporation_tax_expense_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240A' THEN f.total_000s END) AS surplus_continuing_operations_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240B' THEN f.total_000s END) AS surplus_discontinued_operations_000s,
    MAX(CASE WHEN f.sub_code = 'SCI0240'  THEN f.total_000s END) AS surplus_for_year_000s,

    -- Other comprehensive income (OCI)
    MAX(CASE WHEN f.sub_code = 'SOC0100'  THEN f.total_000s END) AS oci_impairments_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0110'  THEN f.total_000s END) AS oci_revaluations_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0120'  THEN f.total_000s END) AS oci_share_ci_associates_jv_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0125'  THEN f.total_000s END) AS oci_fv_gains_equity_instruments_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0130'  THEN f.total_000s END) AS oci_other_gains_losses_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0140'  THEN f.total_000s END) AS oci_pension_remeasurement_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0145'  THEN f.total_000s END) AS oci_gain_loss_transfers_absorption_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0150'  THEN f.total_000s END) AS oci_other_reserve_movements_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0160'  THEN f.total_000s END) AS oci_fv_gains_financial_assets_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0170'  THEN f.total_000s END) AS oci_recycling_gains_disposal_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0180'  THEN f.total_000s END) AS oci_foreign_exchange_gains_000s,
    MAX(CASE WHEN f.sub_code = 'SOC0190'  THEN f.total_000s END) AS total_comprehensive_income_000s

FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC02 SoCI'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;

-- v_balance_sheet: full statutory Statement of Financial Position from TAC03 SoFP, all 40
-- real BAL* lines. Unlike SoCI/EXP, this schedule already stores correctly signed values in
-- the raw data (liabilities negative) -- no sign-flipping needed, values are summed as stored.
DROP VIEW IF EXISTS v_balance_sheet;
CREATE VIEW v_balance_sheet AS
SELECT
    t.org_code,
    t.organisation_name,
    t.sector,
    t.region,
    t.trust_type,
    f.financial_year,

    -- Non-current assets
    MAX(CASE WHEN f.sub_code = 'BAL1100' THEN f.total_000s END) AS intangible_assets_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1110' THEN f.total_000s END) AS property_plant_equipment_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1115' THEN f.total_000s END) AS right_of_use_assets_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1120' THEN f.total_000s END) AS investment_property_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1130' THEN f.total_000s END) AS investments_jv_associates_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1140' THEN f.total_000s END) AS other_investments_nca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1150' THEN f.total_000s END) AS receivables_nca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1170' THEN f.total_000s END) AS other_assets_nca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1180' THEN f.total_000s END) AS total_non_current_assets_000s,

    -- Current assets
    MAX(CASE WHEN f.sub_code = 'BAL1190' THEN f.total_000s END) AS inventories_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1200' THEN f.total_000s END) AS receivables_ca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1210' THEN f.total_000s END) AS other_investments_ca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1220' THEN f.total_000s END) AS other_assets_ca_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1230' THEN f.total_000s END) AS assets_held_for_sale_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1240' THEN f.total_000s END) AS cash_and_cash_equivalents_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1250' THEN f.total_000s END) AS total_current_assets_000s,

    -- Current liabilities
    MAX(CASE WHEN f.sub_code = 'BAL1260' THEN f.total_000s END) AS payables_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1270' THEN f.total_000s END) AS borrowings_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1280' THEN f.total_000s END) AS other_financial_liabilities_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1290' THEN f.total_000s END) AS provisions_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1300' THEN f.total_000s END) AS other_liabilities_cl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1310' THEN f.total_000s END) AS liabilities_disposal_groups_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1320' THEN f.total_000s END) AS total_current_liabilities_000s,

    MAX(CASE WHEN f.sub_code = 'BAL1330' THEN f.total_000s END) AS total_assets_less_current_liabilities_000s,

    -- Non-current liabilities
    MAX(CASE WHEN f.sub_code = 'BAL1340' THEN f.total_000s END) AS payables_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1350' THEN f.total_000s END) AS borrowings_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1360' THEN f.total_000s END) AS other_financial_liabilities_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1370' THEN f.total_000s END) AS provisions_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1380' THEN f.total_000s END) AS other_liabilities_ncl_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1390' THEN f.total_000s END) AS total_non_current_liabilities_000s,

    MAX(CASE WHEN f.sub_code = 'BAL1400' THEN f.total_000s END) AS total_assets_employed_000s,

    -- Taxpayers' and others' equity
    MAX(CASE WHEN f.sub_code = 'BAL1410' THEN f.total_000s END) AS public_dividend_capital_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1420' THEN f.total_000s END) AS revaluation_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1430' THEN f.total_000s END) AS fv_through_oci_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1440' THEN f.total_000s END) AS other_reserves_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1450' THEN f.total_000s END) AS merger_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1460' THEN f.total_000s END) AS income_expenditure_reserve_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1470' THEN f.total_000s END) AS non_controlling_interest_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1490' THEN f.total_000s END) AS charitable_fund_reserves_000s,
    MAX(CASE WHEN f.sub_code = 'BAL1500' THEN f.total_000s END) AS total_equity_000s

FROM nhs_silver.fct_tac f
JOIN nhs_silver.dim_trust t ON f.org_code = t.org_code
WHERE f.worksheet_name = 'TAC03 SoFP'
GROUP BY t.org_code, t.organisation_name, t.sector, t.region, t.trust_type, f.financial_year;
