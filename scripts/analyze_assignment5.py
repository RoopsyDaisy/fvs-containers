import sqlite3
import pandas as pd
import numpy as np
from pathlib import Path

# Configuration
BASE_DB = Path("outputs/assignment5/base/FVSOut.db")
HARV_DB = Path("outputs/assignment5/harv1/FVSOut.db")
PLOTS = [
    "CARB_99",
    "CARB_100",
    "CARB_101",
    "CARB_293",
    "CARB_294",
    "CARB_295",
    "CARB_296",
    "CARB_297",
]


def read_sql_flexible(conn, base_query: str, table_options: list[str]) -> pd.DataFrame:
    """Try multiple table names and return first successful query."""
    for table in table_options:
        try:
            query = base_query.replace("{TABLE}", table)
            return pd.read_sql_query(query, conn)
        except Exception:
            continue
    raise ValueError(f"Could not find any of these tables: {table_options}")


def get_table_averages(db_path, scenario_name):
    print(f"\n--- Analyzing {scenario_name} ---")
    conn = sqlite3.connect(db_path)

    # Read tables (try both FVS_Summary and FVS_Summary2)
    df_sum = read_sql_flexible(
        conn,
        "SELECT StandID, Year, BA, RBdFt FROM {TABLE}",
        ["FVS_Summary", "FVS_Summary2"],
    )

    # Compute table - handle different column names for canopy cover
    # FVS truncates variable names, so PC_CAN_COVER becomes PC_CAN_C
    try:
        df_comp = pd.read_sql_query(
            "SELECT StandID, Year, PC_CAN_C as CANCOV FROM FVS_Compute", conn
        )
    except Exception:
        try:
            df_comp = pd.read_sql_query(
                "SELECT StandID, Year, CANCOV FROM FVS_Compute", conn
            )
        except Exception:
            # Create empty dataframe if no compute table
            df_comp = pd.DataFrame(columns=["StandID", "Year", "CANCOV"])

    # Carbon table (try column name variations)
    try:
        df_carb = read_sql_flexible(
            conn,
            "SELECT StandID, Year, Aboveground_Total_Live, Standing_Dead FROM {TABLE}",
            ["FVS_Carbon", "FVS_Carbon2"],
        )
    except Exception:
        # Try alternate column names
        df_carb = read_sql_flexible(
            conn,
            "SELECT StandID, Year, Total_Stand_Carbon as Aboveground_Total_Live, Dead_Carbon as Standing_Dead FROM {TABLE}",
            ["FVS_Carbon", "FVS_Carbon2"],
        )

    # Harvest Carbon (might be empty for base)
    try:
        df_hrv_carb = read_sql_flexible(
            conn,
            "SELECT StandID, Year, Merch_Carbon_Stored FROM {TABLE}",
            ["FVS_Hrv_Carbon", "FVS_Hrv_Carbon2"],
        )
    except Exception:
        df_hrv_carb = pd.DataFrame(columns=["StandID", "Year", "Merch_Carbon_Stored"])

    conn.close()

    # Filter for our plots
    df_sum = df_sum[df_sum["StandID"].isin(PLOTS)]
    df_comp = df_comp[df_comp["StandID"].isin(PLOTS)]
    df_carb = df_carb[df_carb["StandID"].isin(PLOTS)]
    if not df_hrv_carb.empty:
        df_hrv_carb = df_hrv_carb[df_hrv_carb["StandID"].isin(PLOTS)]

    # Merge dataframes
    # Note: FVS_Compute might have different year steps if not careful, but usually matches cycle
    df_all = df_sum.merge(df_comp, on=["StandID", "Year"], how="left")
    df_all = df_all.merge(df_carb, on=["StandID", "Year"], how="left")

    if not df_hrv_carb.empty:
        df_all = df_all.merge(df_hrv_carb, on=["StandID", "Year"], how="left")
        df_all["Merch_Carbon_Stored"] = df_all["Merch_Carbon_Stored"].fillna(0)
    else:
        df_all["Merch_Carbon_Stored"] = 0

    # Calculate Cumulative Removals
    # First, sort
    df_all = df_all.sort_values(["StandID", "Year"])
    df_all["Cumulative_RBdFt"] = df_all.groupby("StandID")["RBdFt"].cumsum()

    # Group by Year and Calculate Averages
    df_avg = (
        df_all.groupby("Year")
        .agg(
            {
                "BA": "mean",
                "Aboveground_Total_Live": "mean",
                "Standing_Dead": "mean",
                "CANCOV": "mean",
                "Merch_Carbon_Stored": "mean",
                "Cumulative_RBdFt": "mean",
            }
        )
        .reset_index()
    )

    # Round for display
    df_avg = df_avg.round(1)

    print(df_avg.to_string(index=False))

    # Check 2123 BA
    ba_2123 = df_avg[df_avg["Year"] == 2123]["BA"].values[0]
    print(f"\nCheck: Average BA in 2123 = {ba_2123} ft2/ac")

    return df_avg


print("Generating Assignment 5 Tables...")
base_avg = get_table_averages(BASE_DB, "Base Scenario")
harv_avg = get_table_averages(HARV_DB, "Harvest Scenario")
