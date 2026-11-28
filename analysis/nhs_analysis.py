"""
nhs_analysis.py
---------------
Shared helpers for the analysis layer.

- The SQL notebooks (analysis/notebooks/) call sql(): it runs one named query from
  sql/analysis/*.sql against the MySQL warehouse and shows the query above its result, so the
  SQL file stays the single source of every figure.
- The Shiny app (analysis/app/) reads the Parquet files written by
  python/reporting/export_for_analysis.py into analysis/data/, and never touches MySQL.

Units: the warehouse and Parquet files hold £000s (suffix _000s). Charts show £m, converted at
the edge by to_m(), and every chart axis says which unit it uses. Never mix the two in one visual.
"""

import os
import re
from functools import cache
from pathlib import Path

import pandas as pd

ANALYSIS_DIR = Path(__file__).resolve().parent
DATA_DIR = ANALYSIS_DIR / "data"
SQL_DIR = ANALYSIS_DIR.parent / "sql" / "analysis"


# ── SQL: run named queries from sql/analysis/ ───────────────────────────────

@cache
def _connection():
    """One open connection for the whole notebook, so session variables (SET @org_code) persist."""
    from sqlalchemy import create_engine
    from sqlalchemy.engine import URL

    password = os.getenv("DB_PASSWORD")
    if not password:
        raise RuntimeError("DB_PASSWORD environment variable is required for MySQL access")
    url = URL.create(
        drivername="mysql+pymysql",
        username=os.getenv("DB_USER", "root"),
        password=password,
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        database="nhs_gold",
        query={"charset": "utf8mb4"},
    )
    return create_engine(url).connect()


def load_queries(file: str) -> dict[str, str]:
    """Split a sql/analysis file into {name: sql} on its '-- name:' marker lines."""
    text_ = (SQL_DIR / f"{file}.sql").read_text(encoding="utf-8")
    parts = re.split(r"^-- name:\s*(\w+)\s*$", text_, flags=re.MULTILINE)
    return {name: body.strip() for name, body in zip(parts[1::2], parts[2::2])}


def sql(file: str, name: str, show: bool = True, **params) -> pd.DataFrame:
    """
    Run the query called `name` in sql/analysis/<file>.sql and return its last result.

    Keyword arguments become MySQL session variables first, e.g. sql(..., org_code="RGR")
    runs SET @org_code = 'RGR'. With show=True the query is displayed above the result.
    """
    from sqlalchemy import text

    body = load_queries(file)[name]
    conn = _connection()
    for key, value in params.items():
        conn.execute(text(f"SET @{key} = :v"), {"v": value})
    statements = [s.strip() for s in re.split(r";\s*$", body, flags=re.MULTILINE) if s.strip()]
    result = None
    for statement in statements:
        executed = conn.execute(text(statement))
        if executed.returns_rows:
            result = pd.DataFrame(executed.fetchall(), columns=list(executed.keys()))
    if show:
        from IPython.display import Markdown, display
        display(Markdown(f"`sql/analysis/{file}.sql` → **{name}**\n\n```sql\n{body}\n```"))
    if result is None:
        return pd.DataFrame()
    # DECIMAL columns arrive as Decimal objects; make them floats for display and charts
    for col in result.columns:
        if result[col].map(type).astype(str).str.contains("Decimal").any():
            result[col] = pd.to_numeric(result[col])
        # Counts (SUM of flags, COUNT) are whole numbers: show them as integers, not 22.0
        if (pd.api.types.is_float_dtype(result[col]) and result[col].notna().any()
                and (result[col].dropna() % 1 == 0).all()
                and not col.endswith(("_m", "_pct", "_pts"))):
            result[col] = result[col].astype("Int64")
    return result

# Fixed order and fixed colour per sector: a sector keeps its colour on every chart and in
# every filter state (colour follows the entity, never its rank). Slots 1-5 of a validated
# categorical palette, in palette order.
SECTOR_ORDER = ["Acute", "Mental Health", "Community", "Ambulance", "Specialist"]
SECTOR_COLOURS = {
    "Acute":         "#257de0",
    "Mental Health": "#f47230",
    "Community":     "#00b894",
    "Ambulance":     "#f2a600",
    "Specialist":    "#ee7fac",
}

# Diverging pair for polarity (deficit vs surplus) and neutral context colours
DEFICIT = "#ec4647"
SURPLUS = "#257de0"
CONTEXT_GREY = "#c4c4c4"
TEXT = "#191919"
TEXT_SECONDARY = "#666666"


def _read(name: str) -> pd.DataFrame:
    path = DATA_DIR / name
    if not path.exists():
        raise FileNotFoundError(
            f"{path} not found. Run `python python/reporting/export_for_analysis.py` "
            "from the repository root first (needs the MySQL warehouse and DB_PASSWORD)."
        )
    return pd.read_parquet(path)


def load_trust_year() -> pd.DataFrame:
    """One row per trust per financial year, with a derived operating margin and liquidity."""
    df = _read("trust_year.parquet")
    df["sector"] = pd.Categorical(df["sector"], categories=SECTOR_ORDER, ordered=True)
    df["operating_margin_pct"] = (
        df["operating_surplus_000s"] / df["total_income_000s"].where(df["total_income_000s"] != 0) * 100
    )
    # Current liabilities are stored negative (SoFP sign convention), so flip for the ratio
    df["current_ratio"] = (
        df["total_current_assets_000s"]
        / (-df["total_current_liabilities_000s"]).where(df["total_current_liabilities_000s"] < 0)
    )
    # Days of operating cost covered by cash at year end
    daily_cost = df["total_expenditure_000s"] / 365
    df["cash_days"] = df["cash_and_cash_equivalents_000s"] / daily_cost.where(daily_cost > 0)
    return df


def load_expenditure_lines() -> pd.DataFrame:
    """One row per trust per year per TAC08 operating-expense line."""
    df = _read("expenditure_lines.parquet")
    df["sector"] = pd.Categorical(df["sector"], categories=SECTOR_ORDER, ordered=True)
    return df


def financial_years(df: pd.DataFrame) -> list[str]:
    """Financial years present, oldest first ('2021/22' sorts correctly as text)."""
    return sorted(df["financial_year"].unique())


def to_m(value_000s):
    """£000s → £m, for display only."""
    return value_000s / 1000


def fmt_m(value_000s: float) -> str:
    """Format a £000s amount as £m text, e.g. -12,345 → '-£12.3m'."""
    m = to_m(value_000s)
    sign = "-" if m < 0 else ""
    return f"{sign}£{abs(m):,.1f}m"


def set_style() -> None:
    """Recessive grid and axes, text in text inks, for every seaborn chart."""
    import seaborn as sns

    sns.set_theme(
        style="whitegrid",
        rc={
            "axes.edgecolor": "#d9d9d9",
            "axes.labelcolor": TEXT_SECONDARY,
            "axes.titlecolor": TEXT,
            "axes.titleweight": "bold",
            "axes.titlesize": 13,
            "axes.titlelocation": "left",
            "grid.color": "#ececec",
            "xtick.color": TEXT_SECONDARY,
            "ytick.color": TEXT_SECONDARY,
            "text.color": TEXT,
            "figure.dpi": 110,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "legend.frameon": False,
        },
    )
