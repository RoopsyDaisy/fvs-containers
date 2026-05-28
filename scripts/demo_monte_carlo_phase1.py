"""
Demo script for Monte Carlo Phase 1: Parameter Sampling

This script demonstrates how to use the newly implemented MonteCarloConfig
and parameter sampling functionality.
"""

import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from fvs_tools import FVSSimulationConfig
from fvs_tools.monte_carlo import (
    BooleanParameterSpec,
    DiscreteUniformSpec,
    MonteCarloConfig,
    UniformParameterSpec,
    generate_parameter_samples,
)


def main():
    print("=" * 80)
    print("Monte Carlo Phase 1 Demo: Parameter Sampling")
    print("=" * 80)

    # Step 1: Create a base FVS configuration (template)
    print("\n1. Creating base FVS configuration...")
    base_config = FVSSimulationConfig(
        name="monte_carlo_demo",
        num_years=100,
        cycle_length=10,
        output_carbon=True,
        compute_canopy_cover=True,
    )
    print(f"   ✓ Base config: {base_config.name}, {base_config.num_years} years")

    # Step 2: Define parameter specifications
    print("\n2. Defining parameter specifications...")
    param_specs = [
        UniformParameterSpec("thin_q_factor", 1.5, 2.5),
        UniformParameterSpec("thin_residual_ba", 50.0, 80.0),
        UniformParameterSpec("thin_trigger_ba", 80.0, 120.0),
        UniformParameterSpec("min_harvest_volume", 3000.0, 6000.0),
        # Note: These next params need Phase 3 implementation to use in FVS
        # UniformParameterSpec("mortality_multiplier", 0.8, 1.2),
        # BooleanParameterSpec("enable_calibration", probability_true=0.5),
        # DiscreteUniformSpec("fvs_random_seed", 1, 99999),
    ]
    print(f"   ✓ Defined {len(param_specs)} parameters to sample:")
    for spec in param_specs:
        if isinstance(spec, UniformParameterSpec):
            print(f"     - {spec.name}: Uniform({spec.min_value}, {spec.max_value})")
        elif isinstance(spec, BooleanParameterSpec):
            print(f"     - {spec.name}: Boolean(p={spec.probability_true})")
        elif isinstance(spec, DiscreteUniformSpec):
            print(
                f"     - {spec.name}: DiscreteUniform({spec.min_value}, {spec.max_value})"
            )

    # Step 3: Create Monte Carlo configuration
    print("\n3. Creating Monte Carlo configuration...")
    mc_config = MonteCarloConfig(
        batch_seed=42,  # For reproducibility
        n_samples=5,  # Small number for demo
        n_workers=4,
        parameter_specs=param_specs,
        base_config=base_config,
        plot_ids=[99, 100, 101, 293, 294, 295, 296, 297],  # Section 6 plots
    )
    print("   ✓ Monte Carlo config created:")
    print(f"     - Batch ID: {mc_config.batch_id}")
    print(f"     - Batch seed: {mc_config.batch_seed}")
    print(f"     - Number of samples: {mc_config.n_samples}")
    print(f"     - Output directory: {mc_config.output_base}")
    print(f"     - Plot IDs: {mc_config.plot_ids}")

    # Step 4: Generate parameter samples
    print("\n4. Generating parameter samples...")
    samples = generate_parameter_samples(mc_config)
    print(f"   ✓ Generated {len(samples)} parameter samples\n")

    # Display samples
    print("   Sample Details:")
    print("   " + "-" * 76)
    for sample in samples:
        print(f"   Run {sample['run_id']} (seed={sample['run_seed']}):")
        for key, value in sample.items():
            if key not in ["run_id", "run_seed"]:
                if isinstance(value, float):
                    print(f"     - {key}: {value:.2f}")
                else:
                    print(f"     - {key}: {value}")

    # Step 5: Test reproducibility
    print("\n5. Testing reproducibility...")
    mc_config_2 = MonteCarloConfig(
        batch_seed=42,  # Same seed
        n_samples=5,
        parameter_specs=param_specs,
        base_config=base_config,
        plot_ids=[99, 100, 101, 293, 294, 295, 296, 297],
    )
    samples_2 = generate_parameter_samples(mc_config_2)

    if samples == samples_2:
        print("   ✓ Reproducibility verified: Same seed produces identical samples")
    else:
        print("   ✗ WARNING: Reproducibility failed!")

    # Step 6: Test different seed
    print("\n6. Testing different seed...")
    mc_config_3 = MonteCarloConfig(
        batch_seed=123,  # Different seed
        n_samples=5,
        parameter_specs=param_specs,
        base_config=base_config,
        plot_ids=[99, 100, 101, 293, 294, 295, 296, 297],
    )
    samples_3 = generate_parameter_samples(mc_config_3)

    if samples != samples_3:
        print("   ✓ Different seed produces different samples")
        print(
            f"     - Sample 0, thin_q_factor: {samples[0]['thin_q_factor']:.3f} vs {samples_3[0]['thin_q_factor']:.3f}"
        )
    else:
        print("   ✗ WARNING: Different seeds produced identical samples!")

    print("\n" + "=" * 80)
    print("Phase 1 Demo Complete!")
    print("=" * 80)
    print("\nNext steps:")
    print(
        "  - Phase 2: Implement database schema (MC_RunRegistry, MC_RunSummary, MC_TimeSeries)"
    )
    print(
        "  - Phase 3: Add new parameters to FVSSimulationConfig (mortality_multiplier, etc.)"
    )
    print("  - Phase 4: Implement parallel execution with ProcessPoolExecutor")
    print("  - Phase 5: Implement output extraction and metric calculation")
    print("  - Phase 6: Create analysis utilities and demo notebook")


if __name__ == "__main__":
    main()
