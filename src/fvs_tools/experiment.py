"""
Experiment management for parameter sweeps.

Provides utilities for running FVS simulations with systematic
parameter variations and loading batch results for analysis.
"""

import copy
import sqlite3
from datetime import datetime
from pathlib import Path

import pandas as pd

from .batch import run_batch_simulation
from .config import FVSSimulationConfig


def load_batch_registry(registry_db: Path) -> pd.DataFrame:
    """
    Load the batch registry from a SQLite database.

    Args:
        registry_db: Path to batch_registry.db

    Returns:
        DataFrame with all run records
    """
    conn = sqlite3.connect(str(registry_db))
    df = pd.read_sql_query("SELECT * FROM run_registry", conn)
    conn.close()
    return df


def load_batch_results(
    output_base: Path,
    batch_id: str | None = None,
    include_summary: bool = True,
    include_carbon: bool = True,
    include_compute: bool = True,
) -> dict:
    """
    Load all results from a batch run, joining registry with FVS outputs.

    Args:
        output_base: Base output directory containing batch results
        batch_id: Optional batch ID to filter (uses latest if None)
        include_summary: Include FVS_Summary2 data
        include_carbon: Include FVS_Carbon data
        include_compute: Include FVS_Compute data

    Returns:
        Dictionary with:
            - registry: Run registry DataFrame
            - summary_all: Combined summary data (if requested)
            - carbon_all: Combined carbon data (if requested)
            - compute_all: Combined compute data (if requested)
    """
    output_base = Path(output_base)
    registry_db = output_base / "batch_registry.db"

    if not registry_db.exists():
        raise FileNotFoundError(f"No batch registry found at {registry_db}")

    # Load registry
    registry = load_batch_registry(registry_db)

    # Filter by batch_id if specified
    if batch_id:
        registry = registry[registry["batch_id"] == batch_id]
    elif registry["batch_id"].nunique() > 1:
        # Use most recent batch
        latest_batch = registry.sort_values("created_at").iloc[-1]["batch_id"]
        registry = registry[registry["batch_id"] == latest_batch]
        batch_id = latest_batch

    result = {
        "registry": registry,
        "batch_id": batch_id or registry["batch_id"].iloc[0],
    }

    # Load FVS outputs for successful runs
    all_summary = []
    all_carbon = []
    all_compute = []

    for _, row in registry[registry["success"] == 1].iterrows():
        stand_dir = Path(row["output_dir"])
        db_path = stand_dir / "FVSOut.db"

        if not db_path.exists():
            continue

        conn = sqlite3.connect(str(db_path))

        # Add batch tracking columns
        batch_cols = {
            "batch_id": row["batch_id"],
            "run_index": row["run_index"],
        }

        if include_summary:
            try:
                df = pd.read_sql_query("SELECT * FROM FVS_Summary2", conn)
                for col, val in batch_cols.items():
                    df[col] = val
                all_summary.append(df)
            except Exception:
                pass

        if include_carbon:
            try:
                df = pd.read_sql_query("SELECT * FROM FVS_Carbon", conn)
                for col, val in batch_cols.items():
                    df[col] = val
                all_carbon.append(df)
            except Exception:
                pass

        if include_compute:
            try:
                df = pd.read_sql_query("SELECT * FROM FVS_Compute", conn)
                for col, val in batch_cols.items():
                    df[col] = val
                all_compute.append(df)
            except Exception:
                pass

        conn.close()

    if all_summary:
        result["summary_all"] = pd.concat(all_summary, ignore_index=True)
    if all_carbon:
        result["carbon_all"] = pd.concat(all_carbon, ignore_index=True)
    if all_compute:
        result["compute_all"] = pd.concat(all_compute, ignore_index=True)

    return result


class ExperimentBatch:
    """
    Run multiple FVS configurations with systematic parameter variation.

    Example usage:
        >>> base_config = FVSSimulationConfig(name="q_sweep", num_years=100)
        >>> experiment = ExperimentBatch(base_config)
        >>> experiment.add_variation(thin_q_factor=1.5, thin_residual_ba=65)
        >>> experiment.add_variation(thin_q_factor=2.0, thin_residual_ba=65)
        >>> experiment.add_variation(thin_q_factor=2.5, thin_residual_ba=65)
        >>> results = experiment.run(stands, trees, output_base)
    """

    def __init__(self, base_config: FVSSimulationConfig):
        """
        Initialize experiment with a base configuration.

        Args:
            base_config: Base FVS configuration to vary from
        """
        self.base_config = base_config
        self.variations: list[dict] = []

    def add_variation(self, **param_overrides) -> "ExperimentBatch":
        """
        Add a parameter variation to the experiment.

        Args:
            **param_overrides: Parameter values to override in base config

        Returns:
            self (for method chaining)
        """
        self.variations.append(param_overrides)
        return self

    def add_grid(self, **param_ranges) -> "ExperimentBatch":
        """
        Add a grid of parameter combinations.

        Args:
            **param_ranges: Parameter names mapped to lists of values

        Returns:
            self (for method chaining)

        Example:
            >>> experiment.add_grid(
            ...     thin_q_factor=[1.5, 2.0, 2.5],
            ...     thin_residual_ba=[60, 65, 70]
            ... )
            # Creates 9 variations (3 x 3)
        """
        import itertools

        param_names = list(param_ranges.keys())
        param_values = list(param_ranges.values())

        for combo in itertools.product(*param_values):
            variation = dict(zip(param_names, combo, strict=True))
            self.variations.append(variation)

        return self

    def run(
        self,
        stands: pd.DataFrame,
        trees: pd.DataFrame,
        output_base: Path,
        use_database: bool = True,
        input_database: Path | None = None,
    ) -> dict:
        """
        Run all variations across all stands.

        Args:
            stands: DataFrame with stand records
            trees: DataFrame with all tree records
            output_base: Base directory for outputs
            use_database: Use database input (recommended)
            input_database: Path to FVS input database

        Returns:
            Dictionary with:
                - batch_id: Unique batch identifier
                - registry: Combined registry DataFrame
                - results_by_variation: List of result dicts per variation
        """
        output_base = Path(output_base)
        batch_id = datetime.now().strftime("%Y%m%d_%H%M%S")

        print(f"\n{'='*60}")
        print(f"EXPERIMENT BATCH: {self.base_config.name}")
        print(f"Batch ID: {batch_id}")
        print(f"Variations: {len(self.variations)}")
        print(f"Stands: {len(stands)}")
        print(f"Total runs: {len(self.variations) * len(stands)}")
        print(f"{'='*60}\n")

        results_by_variation = []
        all_registries = []

        for var_idx, variation in enumerate(self.variations):
            # Create config for this variation
            config = copy.copy(self.base_config)
            config.run_id = f"{batch_id}_v{var_idx}"

            # Apply overrides
            for param, value in variation.items():
                if hasattr(config, param):
                    setattr(config, param, value)
                else:
                    print(f"Warning: Unknown parameter {param}")

            # Create variation-specific output directory
            var_name = "_".join(f"{k}={v}" for k, v in variation.items())
            var_dir = output_base / f"var_{var_idx}_{var_name}"

            print(f"\n--- Variation {var_idx}: {variation} ---")

            # Run batch
            result = run_batch_simulation(
                stands=stands,
                trees=trees,
                config=config,
                output_base=var_dir,
                use_database=use_database,
                input_database=input_database,
            )

            # Add variation info to result
            result["variation_index"] = var_idx
            result["variation_params"] = variation
            results_by_variation.append(result)

            # Collect registry
            if "registry_db" in result:
                reg = load_batch_registry(result["registry_db"])
                reg["variation_index"] = var_idx
                for k, v in variation.items():
                    reg[f"var_{k}"] = v
                all_registries.append(reg)

        # Combine all registries
        combined_registry = (
            pd.concat(all_registries, ignore_index=True) if all_registries else None
        )

        print(f"\n{'='*60}")
        print(f"EXPERIMENT COMPLETE: {batch_id}")
        total_success = sum(
            r["run_status"]["success"].sum() for r in results_by_variation
        )
        total_runs = sum(len(r["run_status"]) for r in results_by_variation)
        print(f"Total successful: {total_success}/{total_runs}")
        print(f"{'='*60}\n")

        return {
            "batch_id": batch_id,
            "registry": combined_registry,
            "results_by_variation": results_by_variation,
        }
