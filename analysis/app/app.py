"""
NHS Trust Finance Explorer — Shiny for Python app.

An analyst-facing companion to the Power BI report: pick a financial year, a sector and a trust,
then see where the trust sits against its sector peers and which cost lines differ.

Reads the Parquet files in analysis/data/ (written by python/reporting/export_for_analysis.py);
it never connects to MySQL. Monetary values are £000s in the data and £m on screen.

Run from the repository root:
    shiny run analysis/app/app.py
"""

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from shiny import App, reactive, render, ui

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import nhs_analysis as nhs  # noqa: E402

nhs.set_style()

TY = nhs.load_trust_year()
LINES = nhs.load_expenditure_lines()
YEARS = nhs.financial_years(TY)

MEASURES = {
    "operating_margin_pct": "Operating margin (%)",
    "ebitda_margin_pct": "EBITDA margin (%)",
    "pay_pct_income": "Pay as % of income",
    "current_ratio": "Current ratio (assets ÷ liabilities)",
    "cash_days": "Cash, days of operating cost",
}

DATA_NOTE = (
    "Source: NHS England Trust Accounts Consolidation (TAC). Annual, actuals only. Operating surplus "
    "is the SoCI line as reported (SCI0140A), not NHS England's adjusted performance measure, which "
    "excludes impairments. Cost per WTE is not shown: TAC09 WTE is incomplete for several trusts."
)


# ── UI ──────────────────────────────────────────────────────────────────────

app_ui = ui.page_sidebar(
    ui.sidebar(
        ui.input_select("year", "Financial year", choices=YEARS, selected=YEARS[-1]),
        ui.input_select("sector", "Sector", choices=nhs.SECTOR_ORDER, selected="Acute"),
        ui.input_select("trust", "Trust", choices={}),
        ui.input_select("measure", "Benchmark measure", choices=MEASURES),
        ui.hr(),
        ui.p(DATA_NOTE, class_="small text-muted"),
        width=320,
    ),
    ui.layout_columns(
        ui.value_box("Trusts in deficit", ui.output_text("vb_deficit")),
        ui.value_box("Combined operating result", ui.output_text("vb_total")),
        ui.value_box("Median operating margin", ui.output_text("vb_margin")),
        fill=False,
    ),
    ui.navset_card_underline(
        ui.nav_panel(
            "Sector overview",
            ui.output_plot("deficit_share_plot", height="300px"),
            ui.output_plot("margin_dist_plot", height="300px"),
        ),
        ui.nav_panel(
            "Trust benchmark",
            ui.output_plot("benchmark_plot", height="260px"),
            ui.layout_columns(
                ui.output_plot("trend_plot", height="280px"),
                ui.output_data_frame("rank_table"),
                col_widths=(7, 5),
            ),
        ),
        ui.nav_panel(
            "Cost lines",
            ui.p("Each operating-expense line as a share of the trust's total operating expenditure, "
                 "against the median trust in the same sector. Largest differences first.",
                 class_="small text-muted"),
            ui.output_plot("cost_gap_plot", height="420px"),
            ui.output_data_frame("cost_table"),
        ),
    ),
    title="NHS Trust Finance Explorer",
    fillable=False,
)


# ── Server ─────────────────────────────────────────────────────────────────

def server(input, output, session):

    @reactive.calc
    def year_df() -> pd.DataFrame:
        return TY[TY.financial_year == input.year()]

    @reactive.calc
    def sector_df() -> pd.DataFrame:
        return year_df()[year_df().sector == input.sector()]

    # Trust list follows the sector and year; keep the current trust if it is still there
    @reactive.effect
    def _update_trusts():
        d = sector_df().sort_values("organisation_name")
        choices = dict(zip(d.org_code, d.organisation_name))
        current = input.trust()
        selected = current if current in choices else (d.nsmallest(1, "operating_margin_pct").org_code.iloc[0]
                                                        if len(d) else None)
        ui.update_select("trust", choices=choices, selected=selected)

    @reactive.calc
    def trust_name() -> str:
        d = TY[TY.org_code == input.trust()]
        return d.organisation_name.iloc[-1] if len(d) else ""

    # Value boxes (sector, selected year)
    @render.text
    def vb_deficit():
        d = sector_df()
        return f"{int(d.is_deficit.sum())} of {len(d)}" if len(d) else "–"

    @render.text
    def vb_total():
        d = sector_df()
        return nhs.fmt_m(d.operating_surplus_000s.sum()) if len(d) else "–"

    @render.text
    def vb_margin():
        d = sector_df()
        return f"{d.operating_margin_pct.median():.1f}%" if len(d) else "–"

    # Sector overview
    @render.plot
    def deficit_share_plot():
        share = (TY.groupby(["financial_year", "sector"], observed=True)["is_deficit"].mean() * 100).reset_index()
        fig, ax = plt.subplots()
        sns.barplot(data=share, x="financial_year", y="is_deficit", hue="sector",
                    hue_order=nhs.SECTOR_ORDER, palette=nhs.SECTOR_COLOURS, ax=ax,
                    edgecolor="white", linewidth=2)
        ax.set(title="Share of trusts reporting an operating deficit", xlabel=None,
               ylabel="Trusts in deficit (%)", ylim=(0, 100))
        ax.legend(title=None, loc="upper left", bbox_to_anchor=(1.01, 1.0))
        return fig

    @render.plot
    def margin_dist_plot():
        d = year_df()
        col, label = input.measure(), MEASURES[input.measure()]
        fig, ax = plt.subplots()
        sns.boxplot(data=d, y="sector", x=col, order=nhs.SECTOR_ORDER, hue="sector",
                    palette=nhs.SECTOR_COLOURS, legend=False, fliersize=0, width=0.55,
                    boxprops={"alpha": 0.35}, ax=ax)
        sns.stripplot(data=d, y="sector", x=col, order=nhs.SECTOR_ORDER, hue="sector",
                      palette=nhs.SECTOR_COLOURS, legend=False, size=3.5, jitter=0.18,
                      edgecolor="white", linewidth=0.4, ax=ax)
        if col.endswith("margin_pct"):
            ax.axvline(0, color=nhs.TEXT_SECONDARY, linewidth=1, linestyle="--")
        ax.set(title=f"{label} by trust, {input.year()}", xlabel=label, ylabel=None)
        return fig

    # Trust benchmark
    @render.plot
    def benchmark_plot():
        peers = sector_df()
        col, label = input.measure(), MEASURES[input.measure()]
        this = peers[peers.org_code == input.trust()]
        others = peers[peers.org_code != input.trust()]
        fig, ax = plt.subplots()
        ax.scatter(others[col], np.random.default_rng(0).uniform(-0.25, 0.25, len(others)),
                   s=26, color=nhs.CONTEXT_GREY, edgecolor="white", linewidth=0.5, label="Sector peers")
        ax.axvline(peers[col].median(), color=nhs.TEXT_SECONDARY, linewidth=1, linestyle="--",
                   label="Sector median")
        ax.scatter(this[col], np.zeros(len(this)), s=110, color=nhs.SECTOR_COLOURS[input.sector()],
                   edgecolor="white", linewidth=2, zorder=3, label=trust_name())
        ax.set_yticks([]); ax.set_ylim(-0.5, 0.5); ax.grid(axis="y", visible=False)
        ax.set(title=f"{label} against {input.sector()} peers, {input.year()}", xlabel=label)
        ax.legend(loc="upper left", bbox_to_anchor=(1.01, 1.0), fontsize=8)
        return fig

    @render.plot
    def trend_plot():
        col, label = input.measure(), MEASURES[input.measure()]
        med = (TY[TY.sector == input.sector()].groupby("financial_year")[col].median()
               .reset_index().assign(series="Sector median"))
        mine = TY[TY.org_code == input.trust()][["financial_year", col]].assign(series=trust_name())
        d = pd.concat([med, mine])
        fig, ax = plt.subplots()
        sns.lineplot(data=d, x="financial_year", y=col, hue="series", style="series",
                     palette={trust_name(): nhs.SECTOR_COLOURS[input.sector()], "Sector median": nhs.TEXT_SECONDARY},
                     dashes={trust_name(): "", "Sector median": (4, 2)}, markers=True, markersize=8,
                     linewidth=2, ax=ax)
        ax.set(title=f"{label} over time", xlabel=None, ylabel=None)
        ax.legend(title=None, fontsize=8)
        return fig

    @render.data_frame
    def rank_table():
        peers = sector_df().set_index("org_code")
        if input.trust() not in peers.index:
            return pd.DataFrame()
        ranks = peers[list(MEASURES)].rank(pct=True) * 100
        out = pd.DataFrame({
            "Measure": list(MEASURES.values()),
            "Trust": peers.loc[input.trust(), list(MEASURES)].astype(float).round(1).values,
            "Sector median": peers[list(MEASURES)].median().round(1).values,
            "Percentile": ranks.loc[input.trust()].round(0).values,
        })
        return render.DataGrid(out)

    # Cost lines
    @reactive.calc
    def cost_gap() -> pd.DataFrame:
        d = LINES[(LINES.financial_year == input.year()) & (LINES.sector == input.sector())]
        totals = d.groupby("org_code")["amount_000s"].transform("sum")
        d = d.assign(share_pct=d.amount_000s / totals.where(totals != 0) * 100)
        median = d.groupby("line_item")["share_pct"].median().rename("Sector median %")
        mine = d[d.org_code == input.trust()].set_index("line_item")
        out = pd.concat([mine["share_pct"].rename("Trust %"), median], axis=1).fillna(0)
        out["Difference (pts)"] = out["Trust %"] - out["Sector median %"]
        out["Trust £m"] = nhs.to_m(mine["amount_000s"]).reindex(out.index).fillna(0)
        return out.reindex(out["Difference (pts)"].abs().sort_values(ascending=False).index)

    @render.plot
    def cost_gap_plot():
        d = cost_gap().head(12).rename_axis("line_item").reset_index()
        fig, ax = plt.subplots()
        colours = [nhs.DEFICIT if v > 0 else nhs.SURPLUS for v in d["Difference (pts)"]]
        ax.barh(d["line_item"], d["Difference (pts)"], color=colours)
        ax.axvline(0, color=nhs.TEXT_SECONDARY, linewidth=0.8)
        ax.invert_yaxis()
        ax.set(title=f"Cost share against the {input.sector()} median, {input.year()}",
               xlabel="Percentage points (red = trust spends a larger share than the median)", ylabel=None)
        return fig

    @render.data_frame
    def cost_table():
        return render.DataGrid(cost_gap().round(1).rename_axis("Line item").reset_index())


app = App(app_ui, server)
