"""
load_tac_data.py
----------------
Ingests NHS England TAC (Trust Accounts Consolidation) Excel files
into MySQL databases nhs_bronze (staging) and nhs_silver (conformed dims/fact table).

Usage:
    python python/ingestion/load_tac_data.py

Expects files in data/raw/ matching:
    TAC_NHS_trusts_YYYY-YY.xlsx
    TAC_NHS_foundation_trusts_YYYY-YY.xlsx
"""

import logging
import os
import re
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text

from source_integrity import provider_name_key, sha256_file, source_validation_counts

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Config ─────────────────────────────────────────────────────────────────

# Read credentials from environment; never commit passwords.
DB_USER     = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST     = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT     = int(os.getenv("DB_PORT", "3306"))

STG_DB      = "nhs_bronze"
SILVER_DB   = "nhs_silver"

RAW_DIR       = Path("data/raw")
PROCESSED_DIR = Path("data/processed")

YEAR_RE = re.compile(r"(\d{4})-(\d{2})")

RAW_COLUMNS = [
    "OrganisationName", "WorkSheetName", "TableID",
    "MainCode", "RowNumber", "SubCode", "Total",
]

# ── Helpers ────────────────────────────────────────────────────────────────

def get_engine(database: str):
    if not DB_PASSWORD:
        raise RuntimeError("DB_PASSWORD environment variable is required for MySQL access")
    from sqlalchemy.engine import URL
    url = URL.create(
        drivername="mysql+pymysql", username=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT, database=database,
        query={"charset": "utf8mb4"},
    )
    return create_engine(url, echo=False)


def filename_to_financial_year(filename: str) -> str:
    match = YEAR_RE.search(filename)
    if not match:
        raise ValueError(f"Cannot extract financial year from: {filename}")
    return f"{match.group(1)}/{match.group(2)}"


def filename_to_trust_type(filename: str) -> str:
    return "FOUNDATION_TRUST" if "foundation" in filename.lower() else "NHS_TRUST"


def infer_year_type(main_code: str) -> str:
    if "PY" in str(main_code):
        return "PY"
    return "CY"


# ── Readers ────────────────────────────────────────────────────────────────

def read_provider_list(
    path: Path, source_file: str, source_sha256: str, financial_year: str
) -> pd.DataFrame:
    log.info("  Reading provider list...")
    df = pd.read_excel(path, sheet_name="List of Providers", header=0)
    df = df.rename(columns={
        "Full name of Provider": "organisation_name",
        "NHS code":              "org_code",
        "Region":                "region",
        "Sector":                "sector",
        "Comments ":             "comments",
    })
    
    # Handle column name with/without trailing space
    if "Comments" in df.columns and "comments" not in df.columns:
        df = df.rename(columns={"Comments": "comments"})

    # removing trailing spaces from column names
    keep = ["organisation_name", "org_code", "region", "sector", "comments"]
    df = df[[c for c in keep if c in df.columns]].copy()
    
    df = df.dropna(subset=["org_code", "organisation_name"])
    df["org_code"]          = df["org_code"].astype(str).str.strip()
    df["organisation_name"] = df["organisation_name"].astype(str).str.strip()
    df["provider_name_key"] = df["organisation_name"].map(provider_name_key)
    df["source_file"]       = source_file
    df["source_sha256"]     = source_sha256
    df["financial_year"]    = financial_year
    df = df[
        df["org_code"].str.fullmatch(r"[A-Za-z0-9]{3}", na=False)
        & df["organisation_name"].ne("")
    ].copy()
    log.info("  Found %d providers", len(df))
    return df


def find_sheet_name(path: Path, target: str) -> str:
    """Return the actual sheet name matching target case-insensitively."""
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True)
    try:
        for name in wb.sheetnames:
            if name.lower() == target.lower():
                return name
        raise ValueError(f"Sheet '{target}' not found in {path.name}. Available: {wb.sheetnames}")
    finally:
        wb.close()


def read_all_data(
    path: Path, source_file: str, source_sha256: str,
    financial_year: str, trust_type: str,
) -> pd.DataFrame:
    log.info("  Reading All data sheet (this takes ~30s for large files)...")
    sheet_name = find_sheet_name(path, "All data")
    df = pd.read_excel(
        path,
        sheet_name=sheet_name,
        header=0,
        dtype={
            "OrganisationName": str,
            "WorkSheetName":    str,
            "TableID":          "Int64",
            "MainCode":         str,
            "RowNumber":        "Int64",
            "SubCode":          str,
            "Total":            float,
        },
    )

    # Normalise column names across file versions
    # 2023/24: OrganisationName, Total
    # 2021/22: Organisation Name, Value number
    col_map = {
        "Organisation Name": "OrganisationName",
        "Value number":      "Total",
        "Value Number":      "Total",
    }
    df = df.rename(columns=col_map)

    missing = [c for c in RAW_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"Missing columns in {path.name}: {missing}. Found: {list(df.columns)}")

    df = df[RAW_COLUMNS].copy()
    df.columns = ["organisation_name", "worksheet_name", "table_id",
                  "main_code", "row_num", "sub_code", "total"]

    before = len(df)
    df = df.dropna(subset=[
        "organisation_name", "worksheet_name", "table_id", "main_code", "row_num", "sub_code",
    ])
    dropped = before - len(df)
    if dropped:
        log.warning("  Dropped %d null rows", dropped)

    df["organisation_name"] = df["organisation_name"].astype(str).str.strip()
    df["worksheet_name"]    = df["worksheet_name"].astype(str).str.strip()
    df["main_code"]         = df["main_code"].astype(str).str.strip()
    df["sub_code"]          = df["sub_code"].astype(str).str.strip()

    empty_required = (
        df[["organisation_name", "worksheet_name", "main_code", "sub_code"]]
        .eq("")
        .any(axis=1)
    )
    if empty_required.any():
        log.warning("  Dropped %d rows with blank required text fields", empty_required.sum())
        df = df.loc[~empty_required].copy()

    # Preserve CY and PY in Bronze. Silver promotion selects CY only.
    df["year_type"] = df["main_code"].apply(infer_year_type)
    numeric_total = pd.to_numeric(df["total"], errors="coerce")
    invalid_total = df["total"].notna() & numeric_total.isna()
    if invalid_total.any():
        raise ValueError(f"{invalid_total.sum()} non-numeric Total values in {path.name}")
    # TAC contains genuine fractional £000 values (up to five decimal places).
    # Preserve source precision; never round these amounts to whole thousands.
    df["total"]          = numeric_total.round(5)
    df["provider_name_key"] = df["organisation_name"].map(provider_name_key)
    df["source_file"]    = source_file
    df["source_sha256"]  = source_sha256
    df["trust_type"]     = trust_type
    df["financial_year"] = financial_year

    current_rows = df[(df["year_type"] == "CY") & df["total"].notna()]
    log.info("  Preserved %d source rows; %d populated CY rows across %d providers",
             len(df), len(current_rows), current_rows["organisation_name"].nunique())
    return df


# ── Validation ─────────────────────────────────────────────────────────────

def validate(
    data_df: pd.DataFrame, provider_df: pd.DataFrame, filename: str,
    counts: dict[str, int] | None = None,
) -> dict[str, int]:
    errors = []
    for col in [
        "organisation_name", "worksheet_name", "table_id", "main_code", "row_num", "sub_code",
        "financial_year",
    ]:
        nulls = data_df[col].isna().sum()
        if nulls:
            errors.append(f"[CRITICAL] {nulls} nulls in '{col}'")

    counts = counts or source_validation_counts(data_df, provider_df)
    if counts["duplicate_rows"]:
        errors.append(
            f"[CRITICAL] {counts['duplicate_rows']} duplicated source rows at the full source grain"
        )
    if counts["duplicate_fact_key_rows"]:
        errors.append(
            f"[CRITICAL] {counts['duplicate_fact_key_rows']} populated CY rows collide at the fact key"
        )
    if counts["ambiguous_provider_keys"]:
        errors.append(
            f"[CRITICAL] {counts['ambiguous_provider_keys']} normalised provider names map to multiple ODS codes"
        )
    if counts["duplicate_provider_rows"]:
        errors.append(
            f"[CRITICAL] {counts['duplicate_provider_rows']} duplicated provider lookup rows"
        )
    if counts["unmatched_provider_rows"]:
        fact_candidates = data_df[(data_df["year_type"] == "CY") & data_df["total"].notna()]
        provider_keys = set(provider_df["provider_name_key"])
        unmatched = sorted(
            fact_candidates.loc[
                ~fact_candidates["provider_name_key"].isin(provider_keys), "organisation_name"
            ].unique()
        )
        errors.append(
            f"[CRITICAL] {counts['unmatched_provider_rows']} populated CY rows have no provider mapping: "
            f"{unmatched[:10]}"
        )

    if errors:
        for e in errors:
            log.error(e)
        raise ValueError(f"Critical validation failures in {filename}")

    log.info("  Source validation passed: %s", counts)
    return counts


# ── Database loaders ───────────────────────────────────────────────────────

def record_import_batch(
    source_file: str,
    source_sha256: str,
    file_size_bytes: int,
    financial_year: str,
    trust_type: str,
    status: str,
    counts: dict[str, int] | None = None,
    error_message: str | None = None,
) -> None:
    counts = counts or {}
    engine = get_engine(STG_DB)
    sql = text("""
        INSERT INTO import_batch
            (source_file, source_sha256, file_size_bytes, financial_year, trust_type,
             source_rows, current_year_rows, fact_candidate_rows, provider_rows,
             duplicate_rows, duplicate_fact_key_rows, unmatched_provider_rows, ambiguous_provider_keys,
             duplicate_provider_rows, status, error_message)
        VALUES
            (:source_file, :source_sha256, :file_size_bytes, :financial_year, :trust_type,
             :source_rows, :current_year_rows, :fact_candidate_rows, :provider_rows,
             :duplicate_rows, :duplicate_fact_key_rows, :unmatched_provider_rows, :ambiguous_provider_keys,
             :duplicate_provider_rows, :status, :error_message)
        ON DUPLICATE KEY UPDATE
            file_size_bytes = VALUES(file_size_bytes),
            source_rows = VALUES(source_rows),
            current_year_rows = VALUES(current_year_rows),
            fact_candidate_rows = VALUES(fact_candidate_rows),
            provider_rows = VALUES(provider_rows),
            duplicate_rows = VALUES(duplicate_rows),
            duplicate_fact_key_rows = VALUES(duplicate_fact_key_rows),
            unmatched_provider_rows = VALUES(unmatched_provider_rows),
            ambiguous_provider_keys = VALUES(ambiguous_provider_keys),
            duplicate_provider_rows = VALUES(duplicate_provider_rows),
            status = VALUES(status),
            error_message = VALUES(error_message),
            started_ts = CASE WHEN VALUES(status) = 'STARTED'
                              THEN CURRENT_TIMESTAMP ELSE started_ts END,
            completed_ts = CASE
                WHEN VALUES(status) IN ('LOADED', 'FAILED') THEN CURRENT_TIMESTAMP
                WHEN VALUES(status) = 'STARTED' THEN NULL
                ELSE completed_ts
            END
    """)
    params = {
        "source_file": source_file,
        "source_sha256": source_sha256,
        "file_size_bytes": file_size_bytes,
        "financial_year": financial_year,
        "trust_type": trust_type,
        "source_rows": counts.get("source_rows"),
        "current_year_rows": counts.get("current_year_rows"),
        "fact_candidate_rows": counts.get("fact_candidate_rows"),
        "provider_rows": counts.get("provider_rows"),
        "duplicate_rows": counts.get("duplicate_rows"),
        "duplicate_fact_key_rows": counts.get("duplicate_fact_key_rows"),
        "unmatched_provider_rows": counts.get("unmatched_provider_rows"),
        "ambiguous_provider_keys": counts.get("ambiguous_provider_keys"),
        "duplicate_provider_rows": counts.get("duplicate_provider_rows"),
        "status": status,
        "error_message": error_message,
    }
    with engine.begin() as conn:
        conn.execute(sql, params)

def load_staging(data_df: pd.DataFrame, provider_df: pd.DataFrame,
                 financial_year: str, trust_type: str) -> None:
    engine = get_engine(STG_DB)

    with engine.begin() as conn:
        conn.execute(text(
            "DELETE FROM stg_tac_raw WHERE financial_year = :fy AND trust_type = :tt"
        ), {"fy": financial_year, "tt": trust_type})
        conn.execute(text(
            "DELETE FROM stg_provider_list WHERE financial_year = :fy AND trust_type = :tt"
        ), {"fy": financial_year, "tt": trust_type})
        provider_df["trust_type"] = trust_type
        provider_df.to_sql(
            "stg_provider_list", conn, if_exists="append", index=False, chunksize=500
        )
        data_df.to_sql(
            "stg_tac_raw", conn, if_exists="append", index=False, chunksize=2000
        )

    log.info("  Loaded %d rows → nhs_bronze.stg_provider_list", len(provider_df))
    log.info("  Loaded %d rows → nhs_bronze.stg_tac_raw", len(data_df))


def populate_dim_trust(financial_year: str, trust_type: str) -> None:
    stg_engine    = get_engine(STG_DB)
    silver_engine = get_engine(SILVER_DB)

    providers = pd.read_sql(
        "SELECT DISTINCT org_code, organisation_name, sector, region, source_file, financial_year "
        "FROM stg_provider_list "
        "WHERE financial_year = %(fy)s AND trust_type = %(tt)s "
        "AND LENGTH(TRIM(org_code)) = 3",
        stg_engine,
        params={"fy": financial_year, "tt": trust_type},
    )
    if providers.empty:
        log.warning("  No providers found in staging — skipping dim_trust")
        return

    providers["trust_type"]   = providers["source_file"].apply(
        lambda f: "FOUNDATION_TRUST" if "foundation" in f.lower() else "NHS_TRUST"
    )
    providers["is_foundation"] = (providers["trust_type"] == "FOUNDATION_TRUST").astype(int)

    upsert_sql = text("""
        INSERT INTO dim_trust
            (org_code, organisation_name, trust_type, sector, region, is_foundation,
             first_year_seen, last_year_seen)
        VALUES
            (:org_code, :organisation_name, :trust_type, :sector, :region, :is_foundation,
             :financial_year, :financial_year)
        ON DUPLICATE KEY UPDATE
            last_year_seen   = VALUES(last_year_seen),
            sector           = COALESCE(VALUES(sector), sector),
            region           = COALESCE(VALUES(region), region),
            updated_ts       = CURRENT_TIMESTAMP
    """)

    with silver_engine.begin() as conn:
        for _, row in providers.iterrows():
            conn.execute(upsert_sql, {
                "org_code":          row["org_code"],
                "organisation_name": row["organisation_name"],
                "trust_type":        row["trust_type"],
                "sector":            row.get("sector"),
                "region":            row.get("region"),
                "is_foundation":     int(row["is_foundation"]),
                "financial_year":    financial_year,
            })

    log.info("  Upserted %d rows → nhs_silver.dim_trust", len(providers))


def promote_to_fact(financial_year: str, trust_type: str) -> None:
    """Resolve ODS codes and atomically replace one year/trust-type fact scope."""
    stg_engine    = get_engine(STG_DB)
    silver_engine = get_engine(SILVER_DB)

    log.info("  Promoting to fct_tac (year=%s, type=%s)...", financial_year, trust_type)

    # Ensure all worksheet names from this file exist in dim_worksheet
    stg_sheets = pd.read_sql(
        "SELECT DISTINCT worksheet_name FROM stg_tac_raw WHERE financial_year = %(fy)s AND trust_type = %(tt)s",
        stg_engine, params={"fy": financial_year, "tt": trust_type}
    )
    with silver_engine.begin() as conn:
        for ws_name in stg_sheets["worksheet_name"]:
            conn.execute(text("""
                INSERT IGNORE INTO dim_worksheet (worksheet_name, schedule_title, category)
                VALUES (:ws, :ws, 'OTHER')
            """), {"ws": ws_name})

    # Load staging data joined with org_code
    sql = """
        SELECT
            p.org_code,
            r.financial_year,
            r.worksheet_name,
            r.table_id,
            r.main_code,
            r.sub_code,
            r.total          AS total_000s,
            r.trust_type,
            r.source_file,
            r.source_sha256
        FROM stg_tac_raw r
        JOIN stg_provider_list p
            ON  r.provider_name_key = p.provider_name_key
            AND r.financial_year    = p.financial_year
            AND r.trust_type        = p.trust_type
        WHERE r.financial_year = %(fy)s
          AND r.trust_type     = %(tt)s
          AND r.year_type      = 'CY'
          AND r.total IS NOT NULL
    """
    fact_df = pd.read_sql(sql, stg_engine, params={"fy": financial_year, "tt": trust_type})
    log.info("  Joined %d rows ready for fact table", len(fact_df))

    if fact_df.empty:
        raise ValueError("No populated CY rows resolved for fact promotion")

    # Upsert in chunks
    upsert_sql = text("""
        INSERT INTO fct_tac
            (org_code, financial_year, worksheet_name, table_id,
             main_code, sub_code, total_000s, trust_type, source_file, source_sha256)
        VALUES
            (:org_code, :financial_year, :worksheet_name, :table_id,
             :main_code, :sub_code, :total_000s, :trust_type, :source_file, :source_sha256)
        ON DUPLICATE KEY UPDATE
            worksheet_name = VALUES(worksheet_name),
            table_id       = VALUES(table_id),
            total_000s     = VALUES(total_000s),
            source_file    = VALUES(source_file),
            source_sha256  = VALUES(source_sha256),
            load_ts        = CURRENT_TIMESTAMP
    """)

    chunk_size = 1000
    total_rows = 0
    with silver_engine.begin() as conn:
        deleted = conn.execute(
            text("DELETE FROM fct_tac WHERE financial_year = :fy AND trust_type = :tt"),
            {"fy": financial_year, "tt": trust_type},
        ).rowcount
        log.info("  Cleared %d prior fact rows for this source scope", deleted)
        for start in range(0, len(fact_df), chunk_size):
            chunk = fact_df.iloc[start: start + chunk_size]
            conn.execute(upsert_sql, chunk.to_dict(orient="records"))
            total_rows += len(chunk)

    log.info("  Upserted %d rows → nhs_silver.fct_tac", total_rows)


# ── Main ───────────────────────────────────────────────────────────────────

def process_file(path: Path) -> None:
    source_file    = path.name
    financial_year = filename_to_financial_year(source_file)
    trust_type     = filename_to_trust_type(source_file)
    source_sha256  = sha256_file(path)
    file_size      = path.stat().st_size

    log.info("=" * 60)
    log.info("FILE:  %s", source_file)
    log.info("YEAR:  %s  |  TYPE: %s", financial_year, trust_type)
    log.info("=" * 60)

    counts: dict[str, int] = {}
    record_import_batch(
        source_file, source_sha256, file_size, financial_year, trust_type, "STARTED"
    )
    try:
        provider_df = read_provider_list(
            path, source_file, source_sha256, financial_year
        )
        provider_df["trust_type"] = trust_type
        data_df = read_all_data(
            path, source_file, source_sha256, financial_year, trust_type
        )

        counts = source_validation_counts(data_df, provider_df)
        validate(data_df, provider_df, source_file, counts)
        record_import_batch(
            source_file, source_sha256, file_size, financial_year, trust_type,
            "VALIDATED", counts,
        )
        load_staging(data_df, provider_df, financial_year, trust_type)
        populate_dim_trust(financial_year, trust_type)
        promote_to_fact(financial_year, trust_type)
        record_import_batch(
            source_file, source_sha256, file_size, financial_year, trust_type,
            "LOADED", counts,
        )
    except Exception as exc:
        record_import_batch(
            source_file, source_sha256, file_size, financial_year, trust_type,
            "FAILED", counts, str(exc)[:1000],
        )
        raise

    log.info("  DONE: %s\n", source_file)


def main():
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)

    files = sorted(
        p for p in RAW_DIR.glob("TAC_NHS_*.xlsx")
        if "illustrative" not in p.name.lower()
    )

    if not files:
        log.error("No TAC data files found in %s", RAW_DIR)
        return

    log.info("Found %d files to process", len(files))
    for path in files:
        try:
            process_file(path)
        except Exception as exc:
            log.error("FAILED: %s — %s", path.name, exc)
            raise

    # Final counts
    engine = get_engine(SILVER_DB)
    with engine.connect() as conn:
        facts  = conn.execute(text("SELECT COUNT(*) FROM fct_tac")).scalar()
        trusts = conn.execute(text("SELECT COUNT(*) FROM dim_trust")).scalar()

    log.info("=" * 60)
    log.info("COMPLETE")
    log.info("  dim_trust rows : %d", trusts)
    log.info("  fct_tac rows   : %d", facts)
    log.info("=" * 60)


if __name__ == "__main__":
    main()
