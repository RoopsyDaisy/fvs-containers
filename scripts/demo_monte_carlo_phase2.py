"""
Demo script for Monte Carlo Phase 2: Database Layer

Demonstrates the complete database workflow:
- Creating database with schema
- Writing batch metadata and registry
- Writing summary metrics and time series
- Logging errors
- Loading and analyzing results
"""

import sys
from pathlib import Path

import pandas as pd

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from fvs_tools import FVSSimulationConfig
from fvs_tools.monte_carlo import (
    MonteCarloConfig,
    UniformParameterSpec,
    create_mc_database,
    generate_parameter_samples,
    load_mc_results,
    update_batch_status,
    update_run_status,
    write_batch_error,
    write_batch_meta,
    write_run_registry,
    write_run_summary,
    write_time_series,
)


def main():
    print("=" * 80)
    print("Monte Carlo Phase 2 Demo: Database Layer")
    print("=" * 80)

    # Step 1: Create configuration
    print("\n1. Creating Monte Carlo configuration...")
    base_config = FVSSimulationConfig(
        name="demo_phase2",
        num_years=50,
        cycle_length=10,
    )

    mc_config = MonteCarloConfig(
        batch_seed=42,
        n_samples=3,  # Small for demo
        n_workers=2,
        parameter_specs=[
            UniformParameterSpec("thin_q_factor", 1.5, 2.5),
            UniformParameterSpec("thin_residual_ba", 50.0, 80.0),
        ],
        base_config=base_config,
    )
    print(f"   ✓ Batch ID: {mc_config.batch_id}")
    print(f"   ✓ Output directory: {mc_config.output_base}")

    # Step 2: Generate samples
    print("\n2. Generating parameter samples...")
    samples = generate_parameter_samples(mc_config)
    print(f"   ✓ Generated {len(samples)} samples")
    for sample in samples:
        print(
            f"     Run {sample['run_id']}: Q={sample['thin_q_factor']:.2f}, BA={sample['thin_residual_ba']:.1f}"
        )

    # Step 3: Create database
    print("\n3. Creating Monte Carlo database...")
    db_path = mc_config.output_base / "mc_results.db"
    conn = create_mc_database(db_path)
    print(f"   ✓ Database created: {db_path}")

    # Step 4: Write batch metadata
    print("\n4. Writing batch metadata...")
    write_batch_meta(conn, mc_config)
    print("   ✓ Batch metadata written")

    # Step 5: Write run registry
    print("\n5. Pre-populating run registry...")
    write_run_registry(conn, mc_config.batch_id, samples)
    print(f"   ✓ Registered {len(samples)} runs (status=pending)")

    # Step 6: Simulate completing runs
    print("\n6. Simulating run execution...")

    # Run 0: Complete successfully
    print("   • Run 0: Executing...")
    update_run_status(conn, mc_config.batch_id, 0, "running")

    # Simulate results
    summary_metrics = {
        "final_total_carbon": 48.5,
        "avg_carbon_stock": 45.2,
        "final_live_carbon": 38.0,
        "final_dead_carbon": 8.5,
        "final_stored_carbon": 2.0,
        "min_canopy_cover": 42.0,
        "final_canopy_cover": 68.0,
        "cumulative_harvest_bdft": 12500.0,
        "run_duration_sec": 125.3,
        "n_stands": 8,
    }
    write_run_summary(conn, mc_config.batch_id, 0, summary_metrics)

    # Time series data
    ts_data = pd.DataFrame(
        {
            "year": [2023, 2033, 2043, 2053, 2063, 2073],
            "aboveground_c_live": [40.0, 42.0, 38.0, 37.0, 37.5, 38.0],
            "standing_dead_c": [5.0, 6.0, 7.0, 8.0, 8.5, 8.5],
            "total_carbon": [45.0, 48.0, 46.5, 46.5, 47.5, 48.5],
            "canopy_cover_pct": [55.0, 60.0, 58.0, 62.0, 65.0, 68.0],
            "ba": [120.0, 135.0, 110.0, 115.0, 120.0, 125.0],
        }
    )
    write_time_series(conn, mc_config.batch_id, 0, ts_data)
    update_run_status(conn, mc_config.batch_id, 0, "complete", "2024-12-09T10:30:00")
    print("     ✓ Run 0 complete")

    # Run 1: Complete successfully
    print("   • Run 1: Executing...")
    update_run_status(conn, mc_config.batch_id, 1, "running")

    summary_metrics_1 = {
        "final_total_carbon": 52.3,
        "avg_carbon_stock": 49.1,
        "final_live_carbon": 42.0,
        "final_dead_carbon": 9.0,
        "final_stored_carbon": 1.3,
        "min_canopy_cover": 45.0,
        "final_canopy_cover": 72.0,
        "cumulative_harvest_bdft": 9800.0,
        "run_duration_sec": 118.7,
        "n_stands": 8,
    }
    write_run_summary(conn, mc_config.batch_id, 1, summary_metrics_1)

    ts_data_1 = pd.DataFrame(
        {
            "year": [2023, 2033, 2043, 2053, 2063, 2073],
            "aboveground_c_live": [42.0, 43.0, 41.0, 41.5, 42.0, 42.0],
            "standing_dead_c": [6.0, 7.0, 8.0, 9.0, 9.0, 9.0],
            "total_carbon": [48.0, 50.0, 50.3, 51.8, 52.3, 52.3],
            "canopy_cover_pct": [58.0, 63.0, 62.0, 67.0, 70.0, 72.0],
        }
    )
    write_time_series(conn, mc_config.batch_id, 1, ts_data_1)
    update_run_status(conn, mc_config.batch_id, 1, "complete", "2024-12-09T10:32:00")
    print("     ✓ Run 1 complete")

    # Run 2: Failed (simulating a realistic error)
    print("   • Run 2: Executing...")
    update_run_status(conn, mc_config.batch_id, 2, "running")
    write_batch_error(
        conn,
        mc_config.batch_id,
        2,
        None,  # Batch-level failure, not stand-specific
        "FVS_EXECUTION_TIMEOUT",
        "FVS process exceeded 300s timeout. Possible infinite loop or extremely slow convergence.",
    )
    update_run_status(conn, mc_config.batch_id, 2, "failed", "2024-12-09T10:33:00")
    print("     ✗ Run 2 failed (simulated timeout for demo)")

    # Step 7: Update batch status
    print("\n7. Updating batch status...")
    update_batch_status(conn, mc_config.batch_id, "partial")
    print("   ✓ Batch marked as 'partial' (some failures)")

    conn.close()

    # Step 8: Load and analyze results
    print("\n8. Loading results from database...")
    results = load_mc_results(db_path)

    print("\n   Batch Metadata:")
    print(f"     - Batch ID: {results['batch_meta']['batch_id']}")
    print(f"     - Status: {results['batch_meta']['status']}")
    print(f"     - Total samples: {results['batch_meta']['n_samples']}")

    print("\n   Run Registry:")
    registry = results["registry"]
    print(f"     - Total runs: {len(registry)}")
    print(f"     - Complete: {(registry['status'] == 'complete').sum()}")
    print(f"     - Failed: {(registry['status'] == 'failed').sum()}")
    print(f"     - Pending: {(registry['status'] == 'pending').sum()}")

    print("\n   Summary Metrics:")
    summary = results["summary"]
    if len(summary) > 0:
        print(f"     - Runs with metrics: {len(summary)}")
        print(
            f"     - Avg total carbon: {summary['final_total_carbon'].mean():.1f} tons/ac"
        )
        print(f"     - Avg canopy cover: {summary['final_canopy_cover'].mean():.1f}%")
        print(
            f"     - Avg harvest: {summary['cumulative_harvest_bdft'].mean():.0f} bdft/ac"
        )

    print("\n   Time Series:")
    timeseries = results["timeseries"]
    print(f"     - Total observations: {len(timeseries)}")
    print(f"     - Runs with timeseries: {timeseries['run_id'].nunique()}")
    print(
        f"     - Years covered: {timeseries['year'].min()}-{timeseries['year'].max()}"
    )

    print("\n   Errors:")
    errors = results["errors"]
    if len(errors) > 0:
        print(f"     - Failed runs: {len(errors)}")
        for _, error in errors.iterrows():
            stand_info = f" (stand {error['stand_id']})" if error["stand_id"] else ""
            print(f"       Run {error['run_id']}{stand_info}: {error['error_type']}")
            print(f"         {error['error_msg'][:80]}...")

    # Step 9: Demonstrate analysis
    print("\n9. Demonstrating analysis capabilities...")

    # Join registry and summary
    merged = registry.merge(summary, on=["batch_id", "run_id"], how="left")

    print("\n   Parameter → Outcome Analysis:")
    completed_runs = merged[merged["status"] == "complete"]
    if len(completed_runs) > 0:
        print(f"     Completed runs: {len(completed_runs)}")
        print("\n     Run | Q-factor | Residual BA | Final Carbon | Final Canopy")
        print("     " + "-" * 68)
        for _, row in completed_runs.iterrows():
            print(
                f"     {int(row['run_id']):3d} | "
                f"{row['thin_q_factor']:8.2f} | "
                f"{row['thin_residual_ba']:11.1f} | "
                f"{row['final_total_carbon']:12.1f} | "
                f"{row['final_canopy_cover']:12.1f}"
            )

    print("\n" + "=" * 80)
    print("Phase 2 Demo Complete!")
    print("=" * 80)
    print(f"\nDatabase saved to: {db_path}")
    print("\nNext steps:")
    print("  - Phase 3: Add new FVS keywords (FixMort, NoCaLib, RanNSeed)")
    print("  - Phase 4: Implement output extraction from FVS results")
    print("  - Phase 5: Parallel execution with ProcessPoolExecutor")
    print("  - Phase 6: Analysis utilities and demo notebook")


if __name__ == "__main__":
    main()
