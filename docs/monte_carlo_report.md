# Monte Carlo Sampling Framework for FVS Forest Simulations

## Technical Report

**Author:** Rupert Williams  
**790:** 790952500

---

## Executive Summary

This report documents the design and implementation of a Monte Carlo sampling framework for the Forest Vegetation Simulator (FVS). The framework enables systematic uncertainty quantification in forest growth projections by running hundreds of simulations with varying parameter combinations sampled from user-defined distributions.

Key capabilities include:
- Parallel execution of FVS simulations across multiple CPU cores
- Flexible parameter specification with uniform distributions
- Structured storage of results in SQLite databases
- Visualization tools for analysis

The framework transforms FVS from a deterministic projection tool into a probabilistic forecasting system, enabling risk assessment, sensitivity analysis, and robust forest management planning.

---

## Table of Contents

1. [Introduction to Monte Carlo Methods](#1-introduction-to-monte-carlo-methods)
2. [Why Monte Carlo for Forest Modeling](#2-why-monte-carlo-for-forest-modeling)
3. [Framework Architecture](#3-framework-architecture)
4. [Parameter Specification](#4-parameter-specification)
5. [Batch Execution System](#5-batch-execution-system)
6. [Results Database Schema](#6-results-database-schema)
7. [Output Metrics and Aggregation](#7-output-metrics-and-aggregation)
8. [Visualization and Analysis](#8-visualization-and-analysis)
9. [Usage Guide](#9-usage-guide)
10. [Limitations and Considerations](#10-limitations-and-considerations)
11. [Future Development](#11-future-development)

---

## 1. Introduction to Monte Carlo Methods

### 1.1 What is Monte Carlo Simulation?

Monte Carlo simulation is a computational technique that uses repeated random sampling to obtain numerical results. Named after the famous Monaco casino, the method harnesses randomness to solve problems that might be deterministic in principle but are too complex for analytical solutions.

The core concept is elegantly simple:

1. **Define the problem** with uncertain inputs characterized by probability distributions
2. **Randomly sample** input values from those distributions
3. **Run the model** for each sampled combination
4. **Aggregate results** to characterize the output distribution

Rather than asking "What will happen?", Monte Carlo asks "What are the possible outcomes, and how likely is each?"

The method's power comes from the Law of Large Numbers: as sample size increases, the sample mean converges to the true expected value. With modern computing power, we can run many simulations in minutes, building robust statistical pictures of complex systems.

Using the tools outlined here we can run 100 simulations of 268 stands in lubrecht in under an hour using 20 cores. That's 26,800 FVS runs over 100 years (10 year intervals) with options enabled similar to those used in assignment 5.

### 1.3 Mathematical Foundation

For a model $f$ with uncertain inputs $\mathbf{X} = (X_1, X_2, ..., X_k)$, Monte Carlo estimation approximates:

$$E[f(\mathbf{X})] \approx \frac{1}{N} \sum_{i=1}^{N} f(\mathbf{x}_i)$$

where $\mathbf{x}_i$ are samples drawn from the joint distribution of inputs.

The standard error of this estimate decreases as $1/\sqrt{N}$, meaning:
- 100 samples → ~10% precision
- 10,000 samples → ~1% precision
- Diminishing returns beyond a certain point

Note: This approach assumes you know the input parameter uncertainty, and assumes FVS is accurate given a set of parameters, neither of which is likely to be true.

---

## 2. Why Monte Carlo for Forest Modeling

### 2.1 Sources of Uncertainty in FVS

The Forest Vegetation Simulator is a powerful empirical growth model, but it relies on numerous parameters that are inherently uncertain:

**Biological Uncertainty:**
- Background mortality rates vary with climate, pests, and disease
- Growth calibration factors depend on site-specific conditions
- Regeneration success rates fluctuate year to year

**Management Uncertainty:**
- Exact thinning intensities depend on operator decisions
- Harvest thresholds may shift with market conditions
- Treatment timing is subject to operational constraints

**Structural Uncertainty:**
- Model equations are empirical approximations
- Parameter estimates have confidence intervals
- Extrapolation beyond training data adds error

A single deterministic FVS run implicitly assumes perfect knowledge of all these factors—an assumption we know to be false.

### 2.2 The Case for Probabilistic Projections

Consider a forest manager asking: "Will this stand maintain 40% canopy cover over the next 50 years under my proposed management plan?"

A deterministic projection might answer "Yes, minimum canopy is 52%." But this hides the uncertainty. What if mortality is 20% higher than assumed? What if the thinning crew removes more volume than specified?

Monte Carlo simulation provides richer answers:
- "Under baseline assumptions, minimum canopy is 52%"
- "90% of simulations stay above 45% canopy"
- "5% of simulations drop below 40% canopy"
- "Risk of threshold violation is most sensitive to mortality assumptions"

This probabilistic framing enables **risk-aware decision making**.

### 2.3 Applications in Forest Management

| Application | Question Addressed |
|-------------|-------------------|
| **Uncertainty Quantification** | How confident are we in carbon sequestration projections? |
| **Risk Assessment** | What's the probability of violating habitat constraints? |
| **Sensitivity Analysis** | Which parameters most influence harvest volume? |
| **Robust Optimization** | Which strategy performs well across many scenarios? |
| **Scenario Planning** | How do outcomes differ under alternative futures? |

---

## 3. Framework Architecture

### 3.1 System Overview

The Monte Carlo framework wraps the FVS simulation engine with a parameter sampling and batch execution layer:

**[IMAGE PROMPT - System Architecture Diagram]**
> Create a technical system architecture diagram showing the Monte Carlo FVS framework. The diagram should have four main horizontal layers connected by arrows:
> 
> **Layer 1 (Top) - Configuration:** A box labeled "MonteCarloConfig" containing sub-elements: "Parameter Specs", "N Samples", "Base Config", "Random Seed"
> 
> **Layer 2 - Parameter Sampling:** A box labeled "Latin Hypercube / Random Sampling" with a dice icon, showing arrows fanning out to multiple sample boxes labeled "Sample 1", "Sample 2", "...", "Sample N"
> 
> **Layer 3 - Parallel Execution:** Multiple boxes labeled "FVS Worker 1", "FVS Worker 2", through "FVS Worker 20" with tree icons, all running in parallel (indicated by parallel vertical lines)
> 
> **Layer 4 (Bottom) - Results Storage:** A cylinder (database icon) labeled "SQLite Database" with five table labels: "BatchMeta", "RunRegistry", "RunSummary", "TimeSeries", "BatchErrors"
> 
> Use a professional blue and green color scheme. Include small icons: gear for config, dice for sampling, tree for FVS, database cylinder for storage. Draw arrows showing data flow from top to bottom. Style should be clean, modern, suitable for a technical report.

### 3.2 Component Overview

```
fvs_tools/
├── __init__.py           # Public API exports
├── config.py             # FVSSimulationConfig dataclass
├── runner.py             # Single FVS execution
├── batch.py              # Multi-stand batch processing
├── monte_carlo.py        # MC sampling and orchestration
├── results.py            # Output parsing and aggregation
└── database.py           # SQLite result storage
```

**Key Design Principles:**
- **Separation of concerns:** Sampling logic is independent of FVS execution
- **Reproducibility:** Seeded random number generators ensure identical results
- **Fault tolerance:** Failed runs are logged without stopping the batch
- **Parallelism:** Multi-process execution saturates available CPU cores

### 3.3 Data Flow

1. **Configuration** → User specifies parameter distributions and sample count
2. **Sampling** → Framework generates N parameter combinations
3. **Execution** → Each combination runs through the full FVS pipeline
4. **Aggregation** → Per-run metrics are computed from raw outputs
5. **Storage** → All results persist to structured database
6. **Analysis** → User loads results for visualization and interpretation

---

## 4. Parameter Specification

### 4.1 The ParameterSpec System

Parameters are specified using a flexible `ParameterSpec` system that defines both the parameter name and its sampling distribution:

```python
from fvs_tools.monte_carlo import UniformParameterSpec

# Define a parameter with uniform distribution
mortality_spec = UniformParameterSpec(
    name="mortality_multiplier",
    min_value=0.8,
    max_value=1.2
)

# Sample a value
sampled_value = mortality_spec.sample(rng)  # Returns float in [0.8, 1.2]
```

The `name` attribute must match a field in `FVSSimulationConfig`:

```python
@dataclass
class FVSSimulationConfig:
    name: str
    num_years: int = 100
    
    # Thinning parameters
    thin_q_factor: float = 2.0
    thin_residual_ba: float = 65.0
    thin_trigger_ba: float = 100.0
    
    # Mortality
    mortality_multiplier: float = 1.0
    
    # Harvest economics
    min_harvest_volume: float = 4500.0
    
    # ... additional fields
```

### 4.2 Currently Supported Parameters

| Parameter | Type | Default | Typical Range | Effect |
|-----------|------|---------|---------------|--------|
| `thin_q_factor` | float | 2.0 | 1.5 - 2.5 | Controls diameter distribution after thinning (BDq method) |
| `thin_residual_ba` | float | 65.0 | 50 - 80 | Target basal area after thinning (ft²/ac) |
| `thin_trigger_ba` | float | 100.0 | 80 - 130 | Basal area threshold to initiate harvest |
| `mortality_multiplier` | float | 1.0 | 0.5 - 1.5 | Scalar applied to background mortality rates |
| `min_harvest_volume` | float | 4500.0 | 3000 - 6000 | Minimum board feet to justify harvest entry |

### 4.3 Example: 5-Parameter Batch Configuration

```python
from fvs_tools.monte_carlo import (
    MonteCarloConfig,
    UniformParameterSpec,
    run_monte_carlo_batch
)
from fvs_tools.config import FVSSimulationConfig

# Define baseline configuration
base_config = FVSSimulationConfig(
    name="sensitivity_study",
    num_years=100,
    thin_q_factor=2.0,
    thin_residual_ba=65.0,
    thin_trigger_ba=100.0,
    mortality_multiplier=1.0,
    min_harvest_volume=4500.0,
)

# Define parameter distributions
parameter_specs = [
    UniformParameterSpec("thin_q_factor", 1.5, 2.5),
    UniformParameterSpec("thin_residual_ba", 50.0, 75.0),
    UniformParameterSpec("thin_trigger_ba", 95.0, 125.0),
    UniformParameterSpec("mortality_multiplier", 0.8, 1.2),
    UniformParameterSpec("min_harvest_volume", 3500.0, 5500.0),
]

# Create Monte Carlo configuration
mc_config = MonteCarloConfig(
    batch_seed=42,           # For reproducibility
    n_samples=100,           # Number of simulations
    n_workers=20,            # Parallel workers
    parameter_specs=parameter_specs,
    base_config=base_config,
)
```

### 4.4 Sampling Strategy

The current implementation uses **simple random sampling** with independent draws for each parameter. Each run receives a unique `run_seed` derived from the `batch_seed`:

```python
# Pseudocode for parameter sampling
def sample_parameters(mc_config, run_index):
    run_seed = mc_config.batch_seed + run_index
    rng = numpy.random.default_rng(run_seed)
    
    params = {}
    for spec in mc_config.parameter_specs:
        params[spec.name] = spec.sample(rng)
    
    return params, run_seed
```

**Future Enhancement:** Latin Hypercube Sampling (LHS) would provide better coverage of the parameter space with fewer samples, improving efficiency for high-dimensional problems.

---

## 5. Batch Execution System

### 5.1 Parallel Execution Architecture

The batch system uses Python's `multiprocessing` module to execute FVS runs in parallel:

```python
from multiprocessing import Pool

def run_monte_carlo_batch(mc_config, stands, trees, output_dir):
    """Execute Monte Carlo batch with parallel workers."""
    
    # Generate all parameter samples
    run_configs = []
    for i in range(mc_config.n_samples):
        params, run_seed = sample_parameters(mc_config, i)
        config = replace(mc_config.base_config, **params)
        run_configs.append((i, config, run_seed))
    
    # Execute in parallel
    with Pool(processes=mc_config.n_workers) as pool:
        results = pool.starmap(execute_single_run, run_configs)
    
    # Aggregate and store results
    store_results(results, output_dir)
```

### 5.2 Single Run Pipeline

Each Monte Carlo sample executes the full FVS pipeline:

```python
def execute_single_run(run_id, config, run_seed):
    """Execute one FVS simulation with given parameters."""
    
    # 1. Create temporary working directory
    work_dir = create_temp_dir(run_id)
    
    # 2. Initialize SQLite database with stand/tree data
    init_fvs_database(work_dir, stands, trees)
    
    # 3. Generate FVS keyword file from config
    write_keyword_file(work_dir, config)
    
    # 4. Execute FVS binary
    result = run_fvs_binary(work_dir)
    
    # 5. Parse outputs if successful
    if result.success:
        summary_df, carbon_df = parse_fvs_outputs(work_dir)
        metrics = compute_run_metrics(summary_df, carbon_df)
        return RunResult(run_id, config, metrics, success=True)
    else:
        return RunResult(run_id, config, error=result.error, success=False)
```

### 5.3 Performance Characteristics

Batch execution performance scales with available CPU cores:

| Configuration | Time (100 runs, 11 stands, 100 years) |
|---------------|---------------------------------------|
| Sequential (1 worker) | ~50 minutes |
| Parallel (10 workers) | ~6 minutes |
| Parallel (20 workers) | ~3.5 minutes |

The limiting factor is typically I/O (database writes) rather than CPU. Using SSDs significantly improves performance.

### 5.4 Fault Tolerance

The system is designed to complete the batch even if individual runs fail:

```python
# From runner.py - success detection
fvs_success = (
    "STOP 20" in result.stderr or    # Normal completion
    "STOP 10" in result.stderr or    # Completed with warnings
    result.returncode == 0
)

if not fvs_success:
    log_error(run_id, result.stderr)
    # Continue with remaining runs
```

Failed runs are logged to `MC_BatchErrors` table with full error messages for debugging.

---

## 6. Results Database Schema

### 6.1 Database Structure

All results are stored in a SQLite database (`mc_results.db`) with five tables:

**[IMAGE PROMPT - Database Schema Diagram]**
> Create an entity-relationship diagram showing the Monte Carlo results database schema. Use a clean, professional style with rectangular boxes for tables and lines showing relationships.
> 
> **Tables (as boxes with columns listed):**
> 
> 1. **MC_BatchMeta** (header in dark blue)
>    - batch_id (PK, bold)
>    - n_samples
>    - n_workers
>    - status
>    - created_at
>    - config_json
> 
> 2. **MC_RunRegistry** (header in green)
>    - batch_id (FK)
>    - run_id (PK, bold)
>    - run_seed
>    - thin_q_factor
>    - thin_residual_ba
>    - mortality_multiplier
>    - ...
> 
> 3. **MC_RunSummary** (header in green)
>    - batch_id (FK)
>    - run_id (PK, bold)
>    - final_total_carbon
>    - min_canopy_cover
>    - cumulative_harvest_bdft
>    - ...
> 
> 4. **MC_TimeSeries** (header in orange)
>    - batch_id (FK)
>    - run_id (FK)
>    - year
>    - total_carbon
>    - canopy_cover_pct
>    - ba
>    - cumulative_harvest
> 
> 5. **MC_BatchErrors** (header in red)
>    - batch_id (FK)
>    - run_id (FK)
>    - stand_id
>    - error_msg
>    - timestamp
> 
> **Relationships (lines with crow's foot notation):**
> - BatchMeta (1) ——< RunRegistry (many)
> - RunRegistry (1) ——— RunSummary (1)
> - RunRegistry (1) ——< TimeSeries (many)
> - BatchMeta (1) ——< BatchErrors (many)
> 
> Use a white background with subtle gridlines. Tables should have rounded corners and drop shadows. Color-code by table type: config (blue), inputs (green), outputs (orange), errors (red).

### 6.2 Table Descriptions

**MC_BatchMeta** - Batch-level configuration and status
```sql
CREATE TABLE MC_BatchMeta (
    batch_id TEXT PRIMARY KEY,
    n_samples INTEGER,
    n_workers INTEGER,
    status TEXT,  -- 'running', 'completed', 'failed'
    created_at TIMESTAMP,
    completed_at TIMESTAMP,
    config_json TEXT  -- Full configuration for reproducibility
);
```

**MC_RunRegistry** - Sampled parameter values for each run
```sql
CREATE TABLE MC_RunRegistry (
    batch_id TEXT,
    run_id TEXT,
    run_seed INTEGER,
    thin_q_factor REAL,
    thin_residual_ba REAL,
    thin_trigger_ba REAL,
    mortality_multiplier REAL,
    min_harvest_volume REAL,
    PRIMARY KEY (batch_id, run_id)
);
```

**MC_RunSummary** - Aggregated outcome metrics per run
```sql
CREATE TABLE MC_RunSummary (
    batch_id TEXT,
    run_id TEXT,
    final_total_carbon REAL,
    avg_carbon_stock REAL,
    final_live_carbon REAL,
    final_dead_carbon REAL,
    final_stored_carbon REAL,
    min_canopy_cover REAL,
    final_canopy_cover REAL,
    cumulative_harvest_bdft REAL,
    PRIMARY KEY (batch_id, run_id)
);
```

**MC_TimeSeries** - Year-by-year trajectories
```sql
CREATE TABLE MC_TimeSeries (
    batch_id TEXT,
    run_id TEXT,
    year INTEGER,
    total_carbon REAL,
    live_carbon REAL,
    dead_carbon REAL,
    stored_carbon REAL,
    canopy_cover_pct REAL,
    ba REAL,
    tph REAL,
    harvest_bdft REAL,
    cumulative_harvest REAL,
    PRIMARY KEY (batch_id, run_id, year)
);
```

**MC_BatchErrors** - Failed run diagnostics
```sql
CREATE TABLE MC_BatchErrors (
    batch_id TEXT,
    run_id TEXT,
    stand_id TEXT,
    error_msg TEXT,
    traceback TEXT,
    timestamp TIMESTAMP
);
```

### 6.3 Loading Results

The `load_mc_results()` function provides convenient access to all tables:

```python
from fvs_tools.monte_carlo import load_mc_results

# Load all results as DataFrames
results = load_mc_results("outputs/large_mc/mc_results.db")

# Access individual components
batch_meta = results['batch_meta']      # dict
registry = results['registry']          # DataFrame
summary = results['summary']            # DataFrame
timeseries = results['timeseries']      # DataFrame
errors = results['errors']              # DataFrame

print(f"Loaded {len(registry)} runs")
print(f"Time series: {len(timeseries)} year-observations")
print(f"Failed runs: {len(errors)}")
```

---

## 7. Output Metrics and Aggregation

### 7.1 Understanding Flow vs Pool Variables

FVS outputs contain two fundamentally different variable types that require different aggregation approaches:

**Pool Variables (State at a Point in Time)**
- Represent the system state at the end of each period
- Examples: Basal Area, Carbon Stocks, Canopy Cover, Trees Per Acre
- Aggregation: Use values at specific time points (initial, final, min, max, mean)

**Flow Variables (Activity During a Period)**
- Represent quantities that accumulate during each period
- Examples: Harvest Volume (RBdFt), Mortality Volume, Growth
- Aggregation: Sum across periods for cumulative totals

**Critical Distinction Example:**

```python
# WRONG - treating harvest like a pool variable
final_harvest = timeseries[timeseries['year'] == 2123]['harvest_bdft'].values[0]
# This gives only the LAST period's harvest, not the total!

# CORRECT - summing flow across all periods
cumulative_harvest = timeseries['harvest_bdft'].sum()
# This gives total harvest over the entire projection
```

### 7.2 Summary Metric Computation

Each run produces a set of summary metrics computed from the time series:

```python
def compute_run_metrics(summary_df, carbon_df):
    """Compute aggregated metrics for one Monte Carlo run."""
    
    # Carbon metrics (POOL - use specific time points)
    final_year = carbon_df['Year'].max()
    final_carbon = carbon_df[carbon_df['Year'] == final_year]
    
    metrics = {
        'final_total_carbon': (
            final_carbon['Aboveground_Live_Carbon'].sum() +
            final_carbon['Standing_Dead_Carbon'].sum() +
            final_carbon['Forest_Products_Carbon'].sum()
        ),
        'avg_carbon_stock': carbon_df.groupby('Year')['Total_Carbon'].mean().mean(),
        
        # Canopy cover (POOL - use min across years)
        'min_canopy_cover': summary_df.groupby('Year')['CnpyCover'].mean().min(),
        'final_canopy_cover': summary_df[summary_df['Year'] == final_year]['CnpyCover'].mean(),
        
        # Harvest (FLOW - sum across periods)
        'cumulative_harvest_bdft': summary_df.groupby('Year')['RBdFt'].mean().sum(),
    }
    
    return metrics
```

### 7.3 Multi-Stand Aggregation

When a batch includes multiple stands, metrics are computed as stand-area-weighted averages:

```
Per-Year Metric = Σ(stand_value × stand_acres) / Σ(stand_acres)
```

For the current implementation with equal-area stands, this simplifies to a simple mean across stands for each year.

---

## 8. Visualization and Analysis

### 8.1 Spaghetti Plots

Spaghetti plots overlay all simulation trajectories to visualize the full range of possible outcomes:

```python
import matplotlib.pyplot as plt
import numpy as np

def plot_spaghetti(timeseries, metric='total_carbon', max_runs=50):
    """Create spaghetti plot of simulation trajectories."""
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    run_ids = timeseries['run_id'].unique()
    colors = plt.cm.viridis(np.linspace(0, 1, min(len(run_ids), max_runs)))
    
    for i, run_id in enumerate(run_ids[:max_runs]):
        run_data = timeseries[timeseries['run_id'] == run_id].sort_values('year')
        ax.plot(run_data['year'], run_data[metric], 
                color=colors[i], alpha=0.5, linewidth=1)
    
    ax.set_xlabel('Year')
    ax.set_ylabel(metric.replace('_', ' ').title())
    ax.set_title(f'{metric} - {len(run_ids)} Monte Carlo Runs')
    ax.grid(alpha=0.3)
    
    return fig
```

**[REUSE IMAGE: Spaghetti plots from MCResults.ipynb Cell 22]**

### 8.2 Percentile Band Plots

Percentile bands summarize the ensemble by showing the mean trajectory with confidence intervals:

```python
def plot_percentile_bands(timeseries, metric='total_carbon', 
                          percentiles=(5, 95)):
    """Plot mean trajectory with percentile bands."""
    
    # Aggregate by year
    agg = timeseries.groupby('year')[metric].agg([
        'mean',
        lambda x: x.quantile(percentiles[0] / 100),
        lambda x: x.quantile(percentiles[1] / 100)
    ])
    agg.columns = ['mean', 'p_low', 'p_high']
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Plot mean line
    ax.plot(agg.index, agg['mean'], linewidth=2, color='blue', label='Mean')
    
    # Plot confidence band
    ax.fill_between(agg.index, agg['p_low'], agg['p_high'],
                    alpha=0.3, color='blue', 
                    label=f'{percentiles[0]}th-{percentiles[1]}th Percentile')
    
    ax.set_xlabel('Year')
    ax.set_ylabel(metric.replace('_', ' ').title())
    ax.set_title(f'{metric} - Mean with {percentiles[1]-percentiles[0]}% Confidence Band')
    ax.legend()
    ax.grid(alpha=0.3)
    
    return fig
```

**[REUSE IMAGE: Percentile band plots from MCResults.ipynb Cell 23]**

### 8.3 Parameter-Outcome Scatter Plots

Joining the registry (inputs) with summary (outputs) enables sensitivity analysis:

```python
def plot_parameter_sensitivity(registry, summary, 
                                param='mortality_multiplier',
                                outcome='final_total_carbon'):
    """Scatter plot showing parameter-outcome relationship."""
    
    # Join inputs with outputs
    merged = registry.merge(summary, on=['batch_id', 'run_id'])
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ax.scatter(merged[param], merged[outcome], 
               alpha=0.6, edgecolors='black')
    
    # Add trend line
    z = np.polyfit(merged[param], merged[outcome], 1)
    p = np.poly1d(z)
    x_line = np.linspace(merged[param].min(), merged[param].max(), 100)
    ax.plot(x_line, p(x_line), 'r--', linewidth=2, label='Trend')
    
    ax.set_xlabel(param.replace('_', ' ').title())
    ax.set_ylabel(outcome.replace('_', ' ').title())
    ax.set_title(f'Parameter Sensitivity: {param} → {outcome}')
    ax.legend()
    ax.grid(alpha=0.3)
    
    return fig
```

**[REUSE IMAGE: Parameter scatter plot from MCResults.ipynb Cell 19]**

### 8.4 Outcome Distribution Histograms

Histograms show the distribution of outcomes across all simulations:

```python
def plot_outcome_distributions(summary, outcomes=None):
    """Plot histograms of outcome distributions."""
    
    if outcomes is None:
        outcomes = ['final_total_carbon', 'min_canopy_cover', 
                    'cumulative_harvest_bdft']
    
    fig, axes = plt.subplots(1, len(outcomes), figsize=(5*len(outcomes), 4))
    
    for ax, outcome in zip(axes, outcomes):
        values = summary[outcome].dropna()
        ax.hist(values, bins=20, edgecolor='black', alpha=0.7)
        ax.axvline(values.mean(), color='red', linestyle='--', 
                   label=f'Mean: {values.mean():.1f}')
        ax.set_xlabel(outcome.replace('_', ' ').title())
        ax.set_ylabel('Count')
        ax.legend()
        ax.grid(alpha=0.3)
    
    plt.tight_layout()
    return fig
```

**[REUSE IMAGE: Outcome histograms from MCResults.ipynb Cell 16]**

---

## 9. Usage Guide

### 9.1 Environment Setup

The framework requires a Linux environment with the FVS binary and Python dependencies:

```bash
# Clone the repository
git clone https://github.com/RoopsyDaisy/fors591.git
cd fors591

# Install dependencies with uv
uv sync

# Verify FVS binary is accessible
which FVSie  # Should return path to compiled binary
```

Alternatively, use the provided devcontainer for a pre-configured environment:

```bash
# Open in VS Code with Dev Containers extension
code .
# Select "Reopen in Container" when prompted
```

### 9.2 Complete Workflow Example

```python
#!/usr/bin/env python
"""Complete Monte Carlo workflow example."""

from pathlib import Path
import fvs_tools as fvs
from fvs_tools.config import FVSSimulationConfig
from fvs_tools.monte_carlo import (
    MonteCarloConfig,
    UniformParameterSpec,
    run_monte_carlo_batch,
    load_mc_results,
)

# =============================================================================
# 1. Load Input Data
# =============================================================================

data_dir = Path("data")
stands = fvs.load_stands(data_dir / "FVS_Lubrecht_2023_FVS_FVS_StandInit.csv")
trees = fvs.load_trees(data_dir / "FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv")

print(f"Loaded {len(stands)} stands, {len(trees)} trees")

# =============================================================================
# 2. Configure Monte Carlo Batch
# =============================================================================

# Baseline FVS configuration
base_config = FVSSimulationConfig(
    name="lubrecht_mc",
    num_years=100,
    thin_q_factor=2.0,
    thin_residual_ba=65.0,
    thin_trigger_ba=100.0,
    mortality_multiplier=1.0,
    min_harvest_volume=4500.0,
)

# Parameter distributions to sample
parameter_specs = [
    UniformParameterSpec("thin_q_factor", 1.5, 2.5),
    UniformParameterSpec("thin_residual_ba", 50.0, 75.0),
    UniformParameterSpec("thin_trigger_ba", 95.0, 125.0),
    UniformParameterSpec("mortality_multiplier", 0.8, 1.2),
    UniformParameterSpec("min_harvest_volume", 3500.0, 5500.0),
]

# Monte Carlo configuration
mc_config = MonteCarloConfig(
    batch_seed=42,
    n_samples=100,
    n_workers=20,
    parameter_specs=parameter_specs,
    base_config=base_config,
)

# =============================================================================
# 3. Execute Batch
# =============================================================================

output_dir = Path("outputs/lubrecht_mc")
output_dir.mkdir(parents=True, exist_ok=True)

print(f"Starting {mc_config.n_samples} Monte Carlo runs...")
run_monte_carlo_batch(mc_config, stands, trees, output_dir)
print("Batch complete!")

# =============================================================================
# 4. Analyze Results
# =============================================================================

results = load_mc_results(output_dir / "mc_results.db")

registry = results['registry']
summary = results['summary']
timeseries = results['timeseries']
errors = results['errors']

print(f"\n{'='*50}")
print("RESULTS SUMMARY")
print(f"{'='*50}")
print(f"Completed runs: {len(summary)}")
print(f"Failed runs: {len(errors)}")
print(f"\nOutcome Statistics:")
print(f"  Final Carbon: {summary['final_total_carbon'].mean():.1f} ± "
      f"{summary['final_total_carbon'].std():.1f} tons/ac")
print(f"  Min Canopy:   {summary['min_canopy_cover'].mean():.1f} ± "
      f"{summary['min_canopy_cover'].std():.1f} %")
print(f"  Cum Harvest:  {summary['cumulative_harvest_bdft'].mean():.0f} ± "
      f"{summary['cumulative_harvest_bdft'].std():.0f} bdft/ac")

# =============================================================================
# 5. Risk Assessment Example
# =============================================================================

# What fraction of runs violate 40% canopy threshold?
threshold = 40.0
violations = (summary['min_canopy_cover'] < threshold).sum()
violation_pct = 100 * violations / len(summary)

print(f"\nRisk Assessment:")
print(f"  Runs below {threshold}% canopy: {violations}/{len(summary)} "
      f"({violation_pct:.1f}%)")
```

### 9.3 Running Long Batches

For large batches (500+ samples), use `tmux` for persistent execution:

```bash
# Start tmux session
tmux new-session -d -s mc_batch "uv run python scripts/run_large_mc.py 2>&1 | tee mc_batch.log"

# Check progress
tmux attach -t mc_batch

# Detach without stopping: Ctrl+B, then D

# Check log without attaching
tail -f mc_batch.log
```

### 9.4 Notebook-Based Analysis

The `notebooks/MCResults.ipynb` notebook provides an interactive environment for exploring results:

1. Update the database path in Cell 4:
   ```python
   results_db = Path("../outputs/your_batch/mc_results.db")
   ```

2. Run all cells to generate visualizations

3. Export plots for reports:
   - Right-click on any plot → "Save Image As..."
   - Use 300 DPI exports for print quality

---

## 10. Limitations and Considerations

### 10.1 Current Limitations

**Parameter Coverage:**
- Only 5 parameters currently supported for variation
- Treatment timing is fixed (not yet variable)
- Climate scenarios not yet integrated

**Sampling Method:**
- Simple random sampling only
- Latin Hypercube Sampling would improve efficiency
- No correlated parameter sampling

**Computational:**
- Each run requires full FVS execution (~20 seconds)
- Large batches (1000+ runs) require hours of compute time
- Disk space scales with sample count

### 10.2 Interpretation Caveats

**Independence Assumption:**
- Parameters are sampled independently
- In reality, some parameters may be correlated
- Results may overestimate uncertainty if correlations exist

**Distribution Choice:**
- Uniform distributions assume equal likelihood across range
- Real parameter uncertainty may be better represented by normal or triangular distributions
- Distribution choice significantly affects results

**Model Validity:**
- Monte Carlo quantifies parameter uncertainty, not model error
- If the FVS model is biased, all Monte Carlo runs share that bias
- Results are conditional on the model being structurally correct

### 10.3 Recommended Practices

1. **Start small:** Test with 10-20 samples before running hundreds
2. **Check for failures:** Always examine the errors table
3. **Validate ranges:** Ensure parameter ranges are physically meaningful
4. **Document assumptions:** Record why specific distributions were chosen
5. **Sensitivity first:** Run smaller batches varying one parameter at a time before full factorial

---

## 11. Future Development

### 11.1 Planned Enhancements

**Phase 2: Extended Parameters**
- Regeneration parameters (planting density, species mix)
- Site index variation
- Additional mortality factors (fire, insects)

**Phase 3: Advanced Sampling**
- Latin Hypercube Sampling for better coverage
- Correlated parameter sampling
- Importance sampling for rare events

**Phase 4: Climate Integration**
- Temperature/precipitation scenario linkage
- Climate-dependent growth modifiers
- Disturbance probability scenarios

**Phase 5: Optimization Framework**
- Multi-objective optimization
- Robust optimization under uncertainty
- Stochastic programming integration

### 11.2 Roadmap

**[IMAGE PROMPT - Development Roadmap]**
> Create a horizontal timeline/roadmap graphic showing the Monte Carlo FVS development phases. Use a clean, modern infographic style.
> 
> **Timeline Layout (left to right):**
> 
> **Phase 1 (Complete - Green checkmark):**
> - "Core MC Framework"
> - Icons: gears, database
> - Bullet points: Parameter sampling, Parallel execution, SQLite storage
> 
> **Phase 2 (In Progress - Orange progress circle at 60%):**
> - "Extended Parameters"
> - Icons: sliders, tree variations
> - Bullet points: More FVS parameters, Distribution types, Sensitivity tools
> 
> **Phase 3 (Planned - Gray circle outline):**
> - "Climate & Scenarios"
> - Icons: sun/cloud, thermometer
> - Bullet points: Climate projections, Disturbance scenarios, Temporal variation
> 
> **Phase 4 (Future - Dotted outline):**
> - "Optimization & Dashboards"
> - Icons: chart trending up, dashboard
> - Bullet points: Multi-objective optimization, Interactive visualization, Decision support
> 
> Use a gradient background from light blue (past) to white (present) to light gray (future). Include a small legend showing the status icons. Style should be professional and suitable for a technical report or presentation.

### 11.3 Contributing

The project is open source and welcomes contributions:

- **Repository:** https://github.com/RoopsyDaisy/fors591
- **Issues:** Report bugs or request features via GitHub Issues
- **Pull Requests:** Follow existing code style and include tests

---

## Appendix A: Quick Reference

### A.1 Key Classes

| Class | Purpose |
|-------|---------|
| `FVSSimulationConfig` | Configuration for single FVS run |
| `MonteCarloConfig` | Batch configuration with sampling specs |
| `UniformParameterSpec` | Uniform distribution parameter definition |

### A.2 Key Functions

| Function | Purpose |
|----------|---------|
| `load_stands()` | Load stand initialization data |
| `load_trees()` | Load tree list data |
| `run_monte_carlo_batch()` | Execute full MC batch |
| `load_mc_results()` | Load results from database |

### A.3 Database Tables

| Table | Records |
|-------|---------|
| `MC_BatchMeta` | 1 per batch |
| `MC_RunRegistry` | 1 per sample |
| `MC_RunSummary` | 1 per sample |
| `MC_TimeSeries` | n_years per sample |
| `MC_BatchErrors` | Variable (hopefully 0) |

---

## Appendix B: Glossary

**BDq Method:** A thinning prescription that specifies residual Basal area, maximum Diameter, and the q-factor (ratio of trees between diameter classes).

**Canopy Cover:** Percentage of ground area covered by tree crowns; important for wildlife habitat regulations.

**Flow Variable:** A quantity that accumulates over time (e.g., harvest volume).

**FVS (Forest Vegetation Simulator):** USDA Forest Service growth and yield model.

**Latin Hypercube Sampling:** A stratified sampling technique that ensures better coverage of the parameter space than simple random sampling.

**Monte Carlo Simulation:** Computational technique using random sampling to obtain numerical results.

**Pool Variable:** A quantity representing state at a point in time (e.g., standing carbon).

**Spaghetti Plot:** Visualization showing all simulation trajectories overlaid.

---
