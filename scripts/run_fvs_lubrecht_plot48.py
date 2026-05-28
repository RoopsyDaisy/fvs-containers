#!/usr/bin/env python3
"""
FVS Run Script - Lubrecht Plot 48
Runs FVS on simplified Lubrecht plot data using command-line FVS

This script reads the FVS-ready data, generates keyword and tree files,
then runs the standalone FVS executable.

Equivalent to run_fvs_lubrecht_plot48.R but in Python.

Run: python scripts/run_fvs_lubrecht_plot48.py
"""

import os
import sqlite3
import subprocess
from pathlib import Path

import pandas as pd

# =============================================================================
# Configuration
# =============================================================================
FVS_DIR = Path(
    os.environ.get("FVS_LIB_DIR", "/workspaces/fors591/lib/fvs/FVSie_CmakeDir")
)
FVS_BIN = FVS_DIR / "FVSie"
DATA_FILE = Path("/workspaces/fors591/data/plot48_fvsready_simplified.xlsx")
OUTPUT_DIR = Path("/workspaces/fors591/outputs/fvs_lubrecht_plot48_py")


def write_tree_file(trees: pd.DataFrame, stand: pd.Series, filepath: Path) -> None:
    """
    Write FVS tree file in fixed-width format.

    Format: (I4,I4,F8.3,I1,A3,F5.1,F5.1,2F5.1,F5.1,I1,6I2,2I1,I2,2I3,2I1,F3.0)
    Fields: Plot(4) TreeID(4) Count(8.3) History(1) Species(A3) DBH(5.1) DG(5.1)
            HT(5.1) HTTOPK(5.1) HTG(5.1) CRcode(1)
            DAM1(2) SEV1(2) DAM2(2) SEV2(2) DAM3(2) SEV3(2)
            TVAL(1) CUT(1) SLOPE(2) ASPECT(3) PVCODE(3) TOPO(1) SPREP(1) AGE(3)
    """
    lines = []

    for i, (_, tree) in enumerate(trees.iterrows(), start=1):
        # Species code as 3-character string (zero-padded)
        spp_code = f"{int(tree['SPECIES']):03d}"

        # Build the fixed-width line
        # Using string formatting to match exact field widths
        line = (
            f"{int(tree['PLOT_ID']):4d}"  # Plot ID (I4)
            f"{i:4d}"  # Tree ID (I4)
            f"{float(tree['TREE_COUNT']):8.3f}"  # Count (F8.3)
            f"{int(tree['HISTORY']):1d}"  # History (I1)
            f"{spp_code:>3s}"  # Species (A3)
            f"{float(tree['DIAMETER']):5.1f}"  # DBH (F5.1)
            f"{'':5s}"  # DG - blank (F5.1)
            f"{'':5s}"  # HT - blank (F5.1)
            f"{'':5s}"  # HTTOPK - blank (F5.1)
            f"{'':5s}"  # HTG - blank (F5.1)
            f"{'':1s}"  # CRcode - blank (I1)
            f"{'':2s}"  # DAM1 - blank (I2)
            f"{'':2s}"  # SEV1 - blank (I2)
            f"{'':2s}"  # DAM2 - blank (I2)
            f"{'':2s}"  # SEV2 - blank (I2)
            f"{'':2s}"  # DAM3 - blank (I2)
            f"{'':2s}"  # SEV3 - blank (I2)
            f"{'':1s}"  # TVAL - blank (I1)
            f"{'':1s}"  # CUT - blank (I1)
            f"{int(stand['SLOPE']):2d}"  # SLOPE (I2)
            f"{int(stand['ASPECT']):3d}"  # ASPECT (I3)
            f"{str(stand['PV_CODE']):>3s}"  # PVCODE (I3)
            f"{'':1s}"  # TOPO - blank (I1)
            f"{'':1s}"  # SPREP - blank (I1)
            f"{'':3s}"  # AGE - blank (F3.0)
        )
        lines.append(line)

    filepath.write_text("\n".join(lines) + "\n")
    return lines


def write_keyword_file(
    stand: pd.Series, tree_file: str, filepath: Path, num_years: int = 20
) -> None:
    """
    Write FVS keyword file.
    """
    num_cycles = (num_years + 9) // 10  # Ceiling division

    # Elevation in hundreds of feet
    elev_hundreds = float(stand["ELEVFT"]) / 100

    keywords = f"""STDIDENT
{stand['STAND_ID']:<10s}  Lubrecht Plot 48 FVS Run

STDINFO          {int(stand['FOREST']):2d}{str(stand['PV_CODE']):>10s}          {float(stand['ASPECT']):10.1f}{float(stand['SLOPE']):10.1f}{elev_hundreds:10.0f}

INVYEAR   {int(stand['INV_YEAR']):10d}

NUMCYCLE  {num_cycles:10d}

TREEFMT
(I4,I4,F8.3,I1,A3,F5.1,F5.1,2F5.1,F5.1,I1,6I2,2I1,I2,2I3,2I1,F3.0)

TREELIST          0         0         0         0         0         0         0
{tree_file}

DESIGN    {float(stand['BASAL_AREA_FACTOR']):10.1f}         0         0{int(stand['NUM_PLOTS']):10d}         0         0       1.0

NOTRIPLE

ECHOSUM

DATABASE
DSNOUT
FVSOut.db
SUMMARY
END

PROCESS
STOP
"""

    filepath.write_text(keywords)


def run_fvs(keyword_file: Path, working_dir: Path) -> int:
    """
    Run FVS executable with the given keyword file.

    Returns the exit code.
    """
    # FVS reads keyword file from stdin
    result = subprocess.run(
        [str(FVS_BIN)],
        input=keyword_file.name,
        capture_output=True,
        text=True,
        cwd=working_dir,
        timeout=120,
    )

    # Write stdout/stderr to files
    (working_dir / "fvs.out").write_text(result.stdout)
    (working_dir / "fvs.err").write_text(result.stderr)

    return result.returncode


def parse_fvs_output(db_path: Path) -> pd.DataFrame | None:
    """
    Parse FVS output from SQLite database.

    Returns the FVS_Summary table as a DataFrame.
    """
    if not db_path.exists():
        return None

    conn = sqlite3.connect(db_path)

    # List tables
    tables = pd.read_sql_query(
        "SELECT name FROM sqlite_master WHERE type='table'", conn
    )["name"].tolist()

    print(f"Tables in FVSOut.db: {', '.join(tables)}")

    # Get summary if available
    summary_df = None
    if "FVS_Summary" in tables:
        summary_df = pd.read_sql_query("SELECT * FROM FVS_Summary", conn)

    conn.close()
    return summary_df


def main():
    print()
    print("=" * 60)
    print("FVS SIMPLE RUN - Lubrecht Plot 48 (Python)")
    print("=" * 60)

    # -------------------------------------------------------------------------
    # Configuration
    # -------------------------------------------------------------------------
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\nConfiguration:")
    print(f"  FVS Binary: {FVS_BIN}")
    print(f"  Data File:  {DATA_FILE}")
    print(f"  Output Dir: {OUTPUT_DIR}")

    # -------------------------------------------------------------------------
    # Read the input data
    # -------------------------------------------------------------------------
    print("\n--- Loading Data ---")

    stand_df = pd.read_excel(DATA_FILE, sheet_name="FVS_StandInit")
    trees_df = pd.read_excel(DATA_FILE, sheet_name="FVS_TreeInit")

    print(f"Stand data: {len(stand_df)} rows")
    print(f"Tree data: {len(trees_df)} rows")

    # Use the first (only) stand
    stand = stand_df.iloc[0]

    print(f"\nStand: {stand['STAND_ID']}")
    print(f"Variant: {stand['VARIANT']}")
    print(f"Inventory Year: {int(stand['INV_YEAR'])}")
    print(f"Trees: {len(trees_df)}")

    # -------------------------------------------------------------------------
    # FVS Projection Parameters
    # -------------------------------------------------------------------------
    num_years = 20
    num_cycles = (num_years + 9) // 10

    print(f"\nProjection: {num_years} years ({num_cycles} cycles)")

    # -------------------------------------------------------------------------
    # Create FVS Input Files
    # -------------------------------------------------------------------------
    print("\n--- Creating FVS Input Files ---")

    tree_file = OUTPUT_DIR / "run.tre"
    key_file = OUTPUT_DIR / "run.key"

    tree_lines = write_tree_file(trees_df, stand, tree_file)
    print(f"Created tree file: {tree_file.name}")

    print("\nTree file contents:")
    for line in tree_lines:
        print(f"   {line}")

    write_keyword_file(stand, "run.tre", key_file, num_years)
    print(f"\nCreated keyword file: {key_file.name}")

    print("\nKeyword file contents:")
    for line in key_file.read_text().splitlines():
        print(f"   {line}")

    # -------------------------------------------------------------------------
    # Run FVS
    # -------------------------------------------------------------------------
    print("\n--- Running FVS ---")

    try:
        exit_code = run_fvs(key_file, OUTPUT_DIR)
        print(f"FVS exit code: {exit_code}")
    except subprocess.TimeoutExpired:
        print("ERROR: FVS timed out after 120 seconds")
        exit_code = -1
    except Exception as e:
        print(f"ERROR running FVS: {e}")
        exit_code = -1

    # -------------------------------------------------------------------------
    # Check outputs
    # -------------------------------------------------------------------------
    print("\n--- Output Files ---")

    for f in sorted(OUTPUT_DIR.iterdir()):
        if f.is_file():
            size = f.stat().st_size
            print(f"  {f.name:<20s} {size:8d} bytes")

    # Show FVS output (first 50 lines)
    fvs_out = OUTPUT_DIR / "fvs.out"
    if fvs_out.exists():
        print("\n--- FVS Output (first 50 lines) ---")
        lines = fvs_out.read_text().splitlines()[:50]
        for line in lines:
            print(line)

    # Show any errors
    fvs_err = OUTPUT_DIR / "fvs.err"
    if fvs_err.exists():
        err_content = fvs_err.read_text().strip()
        if err_content:
            print("\n--- FVS Errors ---")
            print(err_content)

    # Check for FVS database output
    db_path = OUTPUT_DIR / "FVSOut.db"
    if db_path.exists():
        print("\n--- FVS Database Output ---")
        summary_df = parse_fvs_output(db_path)
        if summary_df is not None:
            print("\nFVS_Summary:")
            print(summary_df.to_string())

    print()
    print("=" * 60)
    print("FVS RUN COMPLETE")
    print(f"Output directory: {OUTPUT_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
