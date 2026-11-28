"""
nhs_analysis.py
---------------
Shared helpers for the analysis layer: the seaborn notebooks (analysis/notebooks/) and the
Shiny app (analysis/app/) both import this, so data loading, sector colours and number
formatting are defined once.

Data comes from the Parquet files written by python/reporting/export_for_analysis.py into
analysis/data/. Nothing here connects to MySQL.

Units: the Parquet files hold £000s (suffix _000s). Charts show £m, converted at the edge by
to_m(), and every chart axis says which unit it uses. Never mix the two in one visual.
"""

from pathlib import Path

import pandas as pd

DATA_DIR = Path(__file__).resolve().parent / "data"

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
