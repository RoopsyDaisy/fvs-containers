# Monte Carlo FVS Batch Runner - Design Document

## Overview

A system to run FVS simulations with randomized input parameters for:
- Sensitivity analysis
- Uncertainty quantification
- Optimization studies
- Robustness testing

## Design Decisions

| Question | Decision |
|----------|----------|
| Batch Structure | **Option A: Cartesian Product** - Each parameter sample applied to ALL stands |
| Time-Series Granularity | `(batch_id, run_id, year)` - aggregated across stands |
| Parameter Correlation | Independent sampling (correlated/macro params future extension) |
| Database Location | Per-batch SQLite: `outputs/mc_batch_{batch_id}/mc_results.db` |
| Parallelization | Within-batch parallel runs, serial result collection |
| Failure Handling | Skip failures, log to error table, report summary at end |
| Stand Selection | Configurable via stand/plot ID lists (same input data as Assignment 5) |
| Mortality Adjustment | Implement via `FixMort` keyword |
| Calibration Toggle | Implement via `NoCaLib` keyword |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MonteCarloConfig                             │
│  - batch_id: str (auto-generated UUID)                          │
│  - batch_seed: int (deterministic reproducibility)              │
│  - n_samples: int                                               │
│  - base_config: FVSSimulationConfig                             │
│  - parameter_specs: list[ParameterSpec]                         │
│  - stand_ids: list[str] | None (filter stands)                  │
│  - plot_ids: list[int] | None (filter by plot)                  │
│  - n_workers: int (CPU parallelism)                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ParameterSpec (Union type)                   │
├─────────────────────────────────────────────────────────────────┤
│  UniformParameterSpec:                                          │
│    - name: str (e.g., "thin_q_factor")                          │
│    - min_value: float                                           │
│    - max_value: float                                           │
│                                                                 │
│  BooleanParameterSpec:                                          │
│    - name: str (e.g., "enable_calibration")                     │
│    - probability_true: float = 0.5                              │
│                                                                 │
│  DiscreteUniformSpec:                                           │
│    - name: str (e.g., "fvs_random_seed")                        │
│    - min_value: int                                             │
│    - max_value: int                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

All tables include `batch_id` as a key for potential future merging.

### MC_RunRegistry
Written BEFORE runs start. One row per run.

```sql
CREATE TABLE MC_RunRegistry (
    batch_id           TEXT NOT NULL,
    run_id             INTEGER NOT NULL,
    run_seed           INTEGER,          -- FVS random seed for this run
    status             TEXT DEFAULT 'pending',  -- pending/running/complete/failed
    created_at         TEXT,
    completed_at       TEXT,
    -- Sampled parameters stored as columns:
    thin_q_factor      REAL,
    thin_residual_ba   REAL,
    thin_trigger_ba    REAL,
    min_harvest_volume REAL,
    mortality_multiplier REAL,
    enable_calibration INTEGER,          -- 0/1
    -- ... additional sampled params as needed
    PRIMARY KEY (batch_id, run_id)
);
```

### MC_RunSummary
One row per completed run (aggregated metrics across all stands).

```sql
CREATE TABLE MC_RunSummary (
    batch_id              TEXT NOT NULL,
    run_id                INTEGER NOT NULL,
    -- Carbon metrics
    final_total_carbon    REAL,   -- Live + Dead + Stored @ final year
    avg_carbon_stock      REAL,   -- Mean total carbon over all years
    final_live_carbon     REAL,
    final_dead_carbon     REAL,
    final_stored_carbon   REAL,
    -- Canopy metrics
    min_canopy_cover      REAL,   -- Minimum across all years
    final_canopy_cover    REAL,
    -- Harvest metrics
    cumulative_harvest_bdft REAL, -- Total board feet removed
    -- Run metadata
    run_duration_sec      REAL,
    n_stands              INTEGER,
    PRIMARY KEY (batch_id, run_id),
    FOREIGN KEY (batch_id, run_id) REFERENCES MC_RunRegistry(batch_id, run_id)
);
```

### MC_TimeSeries
One row per run per year (aggregated across stands).

```sql
CREATE TABLE MC_TimeSeries (
    batch_id              TEXT NOT NULL,
    run_id                INTEGER NOT NULL,
    year                  INTEGER NOT NULL,
    -- Carbon pools
    aboveground_c_live    REAL,
    standing_dead_c       REAL,
    merch_carbon_stored   REAL,
    total_carbon          REAL,   -- Live + Dead + Stored
    -- Stand metrics
    canopy_cover_pct      REAL,
    ba                    REAL,
    tpa                   REAL,
    -- Harvest (per-period)
    harvest_bdft          REAL,
    cumulative_harvest    REAL,
    PRIMARY KEY (batch_id, run_id, year),
    FOREIGN KEY (batch_id, run_id) REFERENCES MC_RunRegistry(batch_id, run_id)
);
```

### MC_BatchErrors
Log of failed runs for debugging.

```sql
CREATE TABLE MC_BatchErrors (
    batch_id    TEXT NOT NULL,
    run_id      INTEGER NOT NULL,
    stand_id    TEXT,
    error_type  TEXT,
    error_msg   TEXT,
    timestamp   TEXT,
    PRIMARY KEY (batch_id, run_id, stand_id)
);
```

### MC_BatchMeta
Metadata about the batch itself.

```sql
CREATE TABLE MC_BatchMeta (
    batch_id      TEXT PRIMARY KEY,
    batch_seed    INTEGER,
    n_samples     INTEGER,
    n_workers     INTEGER,
    created_at    TEXT,
    completed_at  TEXT,
    status        TEXT,  -- running/complete/partial
    config_json   TEXT   -- Full MonteCarloConfig serialized
);
```

---

## Supported Sampled Parameters

### From FVSSimulationConfig (existing)

| Parameter | Type | Keyword Impact |
|-----------|------|----------------|
| `thin_q_factor` | Uniform(1.5, 2.5) | ThinQFA Q parameter |
| `thin_residual_ba` | Uniform(50, 80) | ThinQFA residual BA |
| `thin_trigger_ba` | Uniform(80, 120) | If condition threshold |
| `min_harvest_volume` | Uniform(3000, 6000) | MinHarv volume |
| `thin_min_dbh` | Uniform(1, 4) | ThinQFA small DBH |
| `thin_max_dbh` | Uniform(20, 30) | ThinQFA large DBH |

### New Parameters to Implement

| Parameter | Type | Keyword Impact |
|-----------|------|----------------|
| `mortality_multiplier` | Uniform(0.8, 1.2) | FixMort keyword |
| `enable_calibration` | Boolean(p=0.5) | NoCaLib keyword |
| `fvs_random_seed` | DiscreteUniform(1, 99999) | RanNSeed keyword |

---

## Execution Flow

```
1. User creates MonteCarloConfig
   ↓
2. generate_parameter_samples(config)
   - Uses batch_seed for deterministic RNG
   - Returns list of n_samples parameter dicts
   ↓
3. write_batch_meta() + write_run_registry()
   - Pre-populate database with all planned runs
   ↓
4. run_monte_carlo_batch() with ProcessPoolExecutor
   - Parallel: execute_single_run() for each sample
   - Each run: 
     a. Build FVSSimulationConfig with sampled params
     b. Run FVS for all stands (existing batch machinery)
     c. Extract summary metrics
     d. Return results (or error)
   ↓
5. Serial: Collect results
   - write_run_summary() for each successful run
   - write_time_series() for each successful run
   - write_batch_errors() for failures
   - Update run status in registry
   ↓
6. Return path to results database
```

---

## File Structure

```
src/fvs_tools/
├── __init__.py              # Add monte_carlo exports
├── monte_carlo/
│   ├── __init__.py          # Public API
│   ├── config.py            # MonteCarloConfig, ParameterSpec classes
│   ├── sampler.py           # Parameter sampling logic
│   ├── database.py          # Schema creation, read/write functions
│   ├── executor.py          # Parallel execution logic
│   ├── outputs.py           # Extract metrics from FVS outputs
│   └── analysis.py          # Convenience functions for analysis
```

---

## Example Usage

```python
from fvs_tools import load_stands, load_trees, filter_by_plot_ids
from fvs_tools.monte_carlo import (
    MonteCarloConfig,
    UniformParameterSpec,
    BooleanParameterSpec,
    DiscreteUniformSpec,
    run_monte_carlo_batch,
    load_mc_results,
)

# Load data (same as Assignment 5)
stands = load_stands()
trees = load_trees()

# Define parameter space
param_specs = [
    UniformParameterSpec("thin_q_factor", 1.5, 2.5),
    UniformParameterSpec("thin_residual_ba", 50.0, 80.0),
    UniformParameterSpec("thin_trigger_ba", 80.0, 120.0),
    UniformParameterSpec("min_harvest_volume", 3000.0, 6000.0),
    UniformParameterSpec("mortality_multiplier", 0.8, 1.2),
    BooleanParameterSpec("enable_calibration", probability_true=0.5),
    DiscreteUniformSpec("fvs_random_seed", 1, 99999),
]

# Configure batch
mc_config = MonteCarloConfig(
    batch_seed=42,
    n_samples=100,
    n_workers=8,
    plot_ids=[99, 100, 101, 293, 294, 295, 296, 297],  # Section 6
    parameter_specs=param_specs,
    base_fvs_config={
        "num_years": 100,
        "cycle_length": 10,
        "output_carbon": True,
        "compute_canopy_cover": True,
    },
)

# Run batch
results_db = run_monte_carlo_batch(
    mc_config,
    stands=stands,
    trees=trees,
    output_dir="../outputs/mc_sensitivity_test",
)

# Load and analyze
registry, summary, timeseries = load_mc_results(results_db)

# Join for sensitivity analysis
df = registry.merge(summary, on=["batch_id", "run_id"])
print(df[["thin_q_factor", "mortality_multiplier", "final_total_carbon"]].corr())
```

---

## Implementation Plan

### Phase 1: Data Structures & Sampling
**Files:** `config.py`, `sampler.py`

- [ ] `UniformParameterSpec` dataclass
- [ ] `BooleanParameterSpec` dataclass
- [ ] `DiscreteUniformSpec` dataclass
- [ ] `MonteCarloConfig` dataclass with validation
- [ ] `generate_parameter_samples()` function
- [ ] Unit tests for deterministic sampling

### Phase 2: Database Layer
**Files:** `database.py`

- [ ] `create_mc_database()` - initialize schema
- [ ] `write_batch_meta()` - save config
- [ ] `write_run_registry()` - pre-populate runs
- [ ] `update_run_status()` - mark complete/failed
- [ ] `write_run_summary()` - insert metrics
- [ ] `write_time_series()` - insert per-year data
- [ ] `write_batch_error()` - log failures
- [ ] `load_mc_results()` - convenience loader

### Phase 3: FVS Integration
**Files:** `config.py` updates, `keyword_builder.py` updates

- [ ] Add `mortality_multiplier` to FVSSimulationConfig
- [ ] Add `enable_calibration` to FVSSimulationConfig  
- [ ] Add `fvs_random_seed` to FVSSimulationConfig
- [ ] Update keyword builder for FixMort
- [ ] Update keyword builder for NoCaLib
- [ ] Update keyword builder for RanNSeed

### Phase 4: Output Extraction
**Files:** `outputs.py`

- [ ] `extract_run_summary()` - compute aggregate metrics
- [ ] `extract_time_series()` - extract per-year data
- [ ] Handle missing/partial outputs gracefully

### Phase 5: Parallel Executor
**Files:** `executor.py`

- [ ] `execute_single_run()` - run one sample across all stands
- [ ] `run_monte_carlo_batch()` - orchestrate parallel execution
- [ ] Progress reporting
- [ ] Error capture and logging

### Phase 6: Analysis & Demo
**Files:** `analysis.py`, `notebooks/MonteCarlo_Demo.ipynb`

- [ ] Sensitivity analysis helpers
- [ ] Plotting utilities (uncertainty bands, parameter importance)
- [ ] Demo notebook with full workflow

---

## Dependencies

- Python 3.10+
- pandas
- concurrent.futures (stdlib)
- sqlite3 (stdlib)
- tqdm (for progress bars, optional)
- Existing fvs_tools modules

---

## Estimated Effort

| Phase | Hours | Status |
|-------|-------|--------|
| 1. Data Structures & Sampling | 2-3 | Not started |
| 2. Database Layer | 2-3 | Not started |
| 3. FVS Integration | 3-4 | Not started |
| 4. Output Extraction | 2-3 | Not started |
| 5. Parallel Executor | 4-5 | Not started |
| 6. Analysis & Demo | 3-4 | Not started |
| **Total** | **16-22** | |

---

## Future Extensions (Out of Scope)

- Correlated/macro parameters (one sample affects multiple FVS inputs)
- Non-uniform distributions (normal, log-normal, etc.)
- Bayesian optimization for parameter tuning
- Cross-batch database merging
- Distributed execution (multiple machines)
