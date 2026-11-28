"""
nhs_analysis.py
---------------
Shared helpers for the SQL analysis notebooks (analysis/notebooks/).

The notebooks call sql(): it runs one named query from sql/analysis/*.sql against the MySQL
warehouse and shows the query above its result, so the SQL file stays the single source of every
figure. The rest of this module is chart styling: fixed sector colours and a shared seaborn theme.

Units: the warehouse holds £000s (suffix _000s); the queries convert to £m (suffix _m) for
reading. Never mix the two in one chart.
"""

import os
import re
from functools import cache
from pathlib import Path

import pandas as pd

ANALYSIS_DIR = Path(__file__).resolve().parent
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
