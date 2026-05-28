#!/usr/bin/env python3
"""
Assignment 5: FVS Simulation Runner

Runs the required FVS scenarios for Assignment 5:
1. Base run (Carbon output)
2. Harvest scenarios (MINHARV + THINQ)

Uses the fvs_tools package for modular execution with Web GUI-compatible
keyword generation that produces accurate calibration results.

Expected output: Average BA at year 2123 ≈ 161 ft²/ac for base scenario.
"""

import shutil
import sys
import pandas as pd
import sqlite3
from pathlib import Path

# Add src to path
sys.path.append(str(Path(__file__).parent.parent / "src"))

from fvs_tools.db_input import create_fvs_input_db
from fvs_tools.keyword_builder import build_keyword_file
from fvs_tools.runner import run_fvs
from fvs_tools.scenarios import generate_assignment5_scenarios
from fvs_tools.config import DEFAULT_STAND_DATA, DEFAULT_TREE_DATA, DEFAULT_FVS_BIN

# Configuration
OUTPUT_BASE_DIR = Path("outputs/assignment5")
# Plots for Assignment 5: Section 6 plots (99-101 and 293-297)
PLOT_IDS = [
    "CARB_99",
    "CARB_100",
    "CARB_101",
    "CARB_293",
    "CARB_294",
    "CARB_295",
    "CARB_296",
    "CARB_297",
]


def clear_output_directory(output_dir: Path) -> None:
    """Clear previous output to ensure fresh results."""
    if output_dir.exists():
        print(f"Clearing previous output: {output_dir}")
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)


def main():
    print("============================================================")
    print("Assignment 5: FVS Simulation Runner")
    print("============================================================")

    # Clear previous output
    clear_output_directory(OUTPUT_BASE_DIR)

    # 1. Setup Input Database
    print("\n[1/3] Setting up input database...")
    db_dir = OUTPUT_BASE_DIR / "input_db"
    db_dir.mkdir(parents=True, exist_ok=True)
    db_path = db_dir / "FVS_Data.db"

    # Load data
    print(f"Loading data from:\n  {DEFAULT_STAND_DATA}\n  {DEFAULT_TREE_DATA}")
    stands_df = pd.read_csv(DEFAULT_STAND_DATA)
    trees_df = pd.read_csv(DEFAULT_TREE_DATA)

    # Filter for specific stands
    print(f"Filtering for {len(PLOT_IDS)} plots: {PLOT_IDS}")
    stands_df = stands_df[stands_df["STAND_ID"].isin(PLOT_IDS)]
    trees_df = trees_df[trees_df["STAND_ID"].isin(PLOT_IDS)]

    if stands_df.empty:
        print("Error: No matching stands found in input data!")
        return

    # Create the database
    create_fvs_input_db(stands=stands_df, trees=trees_df, output_db=db_path)
    print(f"Database created at: {db_path}")

    # Load stand data for keyword generation
    conn = sqlite3.connect(db_path)
    # Get all stands from DB
    stands_db = pd.read_sql("SELECT * FROM FVS_StandInit", conn)
    conn.close()

    # 2. Generate Scenarios
    print("\n[2/3] Generating scenarios...")
    scenarios = generate_assignment5_scenarios()
    print(f"Generated {len(scenarios)} scenarios:")
    for s in scenarios:
        print(f"  - {s.name}: {s.description}")

    # 3. Run Simulations
    print("\n[3/3] Running simulations...")

    results = []

    for i, scenario in enumerate(scenarios, 1):
        print(f"\nRunning Scenario {i}/{len(scenarios)}: {scenario.name}")

        # Setup scenario directory
        scenario_dir = OUTPUT_BASE_DIR / scenario.name
        scenario_dir.mkdir(parents=True, exist_ok=True)

        # Run for each stand
        for _, stand in stands_db.iterrows():
            stand_id = stand["Stand_ID"]
            # print(f"  Processing {stand_id}...")

            # Build keyword file
            key_path = scenario_dir / f"{stand_id}.key"
            build_keyword_file(
                stand=stand,
                tree_filename="FVS_Data.db",  # DSNin filename
                config=scenario.config,
                filepath=key_path,
                use_database=True,
            )

            # Run FVS
            try:
                run_result = run_fvs(
                    keyword_file=key_path,
                    working_dir=scenario_dir,
                    fvs_binary=DEFAULT_FVS_BIN,
                    input_database=db_path,
                )

                status = "Success" if run_result["success"] else "Failed"
                if not run_result["success"]:
                    print(f"  {stand_id}: Failed")
                    print(run_result["stderr"])

                results.append(
                    {
                        "scenario": scenario.name,
                        "stand": stand_id,
                        "status": status,
                        "dir": str(scenario_dir),
                    }
                )

            except Exception as e:
                print(f"  {stand_id}: Exception: {e}")
                results.append(
                    {
                        "scenario": scenario.name,
                        "stand": stand_id,
                        "status": "Error",
                        "error": str(e),
                    }
                )

        print(f"  Completed {len(stands_db)} stands.")

    print("\n============================================================")
    print("Summary")
    print("============================================================")

    # Group results by scenario
    df_res = pd.DataFrame(results)
    if not df_res.empty:
        summary = df_res.groupby(["scenario", "status"]).size().unstack(fill_value=0)
        print(summary)
    else:
        print("No results.")

    print(f"\nAll outputs in: {OUTPUT_BASE_DIR}")

    # Validate base scenario BA at 2123
    print("\n============================================================")
    print("Validation: Base Scenario BA at Year 2123")
    print("============================================================")

    base_db = OUTPUT_BASE_DIR / "base" / "FVSOut.db"
    if base_db.exists():
        conn = sqlite3.connect(base_db)
        try:
            # Try FVS_Summary2 first (Web GUI style), then FVS_Summary
            try:
                df = pd.read_sql_query(
                    "SELECT StandID, Year, BA FROM FVS_Summary2 WHERE Year = 2123", conn
                )
            except:
                df = pd.read_sql_query(
                    "SELECT StandID, Year, BA FROM FVS_Summary WHERE Year = 2123", conn
                )

            if not df.empty:
                avg_ba = df["BA"].mean()
                print(f"\nPer-stand BA at 2123:")
                for _, row in df.iterrows():
                    print(f"  {row['StandID']}: {row['BA']:.1f} ft²/ac")
                print(f"\n*** AVERAGE BA 2123: {avg_ba:.1f} ft²/ac ***")
                print(f"*** TARGET: ~161 ft²/ac ***")

                if 158 <= avg_ba <= 164:
                    print("✓ VALIDATION PASSED")
                else:
                    print(
                        f"⚠ WARNING: BA differs from target by {abs(161 - avg_ba):.1f} ft²/ac"
                    )
            else:
                print("No 2123 data found in output database.")
        finally:
            conn.close()
    else:
        print(f"Base scenario database not found: {base_db}")


if __name__ == "__main__":
    main()
