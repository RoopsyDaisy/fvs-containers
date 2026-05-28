# Phase 5: Parallel Executor Implementation Plan

## Status: Ready for Implementation

**Dependencies:** Phases 1-4 complete (93 tests passing)

---

## Intent

Create `executor.py` to orchestrate parallel Monte Carlo batch runs across multiple worker processes. This is the core module that ties together all the infrastructure from Phases 1-4:

- **Phase 1** (config/sampling): `MonteCarloConfig` defines the batch, `generate_parameter_samples()` creates samples
- **Phase 2** (database): Store batch metadata, run registry, summaries, and time series
- **Phase 3** (FVS integration): `FVSSimulationConfig` accepts mortality_multiplier, enable_calibration, fvs_random_seed
- **Phase 4** (outputs): `extract_run_summary()` and `extract_time_series()` process FVS results

---

## Touched Modules

| Module | Changes |
|--------|---------|
| `src/fvs_tools/monte_carlo/executor.py` | **NEW** - Core execution logic |
| `src/fvs_tools/monte_carlo/__init__.py` | Add exports for `run_monte_carlo_batch` |
| `tests/test_monte_carlo_executor.py` | **NEW** - Unit tests |
| `tests/test_monte_carlo_integration.py` | Add integration test for full batch |

---

## Data/Compute Implications

- **Parallelism:** Uses `concurrent.futures.ProcessPoolExecutor` for CPU-bound FVS runs
- **Memory:** Each worker loads stands/trees data independently (small overhead ~10MB)
- **I/O:** Results written to SQLite database (thread-safe via serial writes after parallel runs)
- **Scaling:** For 100 samples × 8 stands × 11 cycles ≈ 800+ FVS cycles; with 8 workers, ~100 FVS runs in parallel

---

## API Design

### Primary Function: `run_monte_carlo_batch()`

```python
def run_monte_carlo_batch(
    mc_config: MonteCarloConfig,
    stands: pd.DataFrame,
    trees: pd.DataFrame,
    output_dir: Path | str,
    progress_callback: Callable[[int, int], None] | None = None,
) -> Path:
    """
    Execute Monte Carlo batch simulation with parallel workers.

    Args:
        mc_config: Monte Carlo configuration (n_samples, parameter_specs, etc.)
        stands: Stand data (will be filtered by mc_config.plot_ids if set)
        trees: Tree data (will be filtered to match stands)
        output_dir: Directory for FVS outputs and results database
        progress_callback: Optional callback(completed, total) for progress updates

    Returns:
        Path to results SQLite database

    Raises:
        ValueError: If configuration is invalid
        RuntimeError: If all runs fail

    Example:
        >>> results_db = run_monte_carlo_batch(mc_config, stands, trees, "./outputs/mc_run")
        >>> registry, summary, timeseries = load_mc_results(results_db)
    """
```

### Helper Function: `execute_single_run()`

```python
def execute_single_run(
    run_params: dict,
    stands: pd.DataFrame,
    trees: pd.DataFrame,
    base_config: dict,
    output_dir: Path,
) -> dict:
    """
    Execute a single Monte Carlo run (all stands with one parameter set).

    This function is called by worker processes. It:
    1. Creates FVSSimulationConfig with sampled parameters
    2. Runs batch simulation for all stands
    3. Extracts summary and time series
    4. Returns results dict (or error info)

    Args:
        run_params: Sampled parameters including run_id and run_seed
        stands: Stand data
        trees: Tree data
        base_config: Base FVS config (num_years, cycle_length, etc.)
        output_dir: Directory for this run's outputs

    Returns:
        dict with keys:
            - run_id: int
            - success: bool
            - summary: dict (from extract_run_summary)
            - time_series: pd.DataFrame (from extract_time_series)
            - error: str | None
    """
```

---

## Implementation Details

### 1. Execution Flow

```
run_monte_carlo_batch(mc_config, stands, trees, output_dir)
│
├── 1. Validate inputs
│   ├── Check mc_config is valid
│   ├── Filter stands/trees by plot_ids (if specified)
│   └── Create output_dir if needed
│
├── 2. Initialize database
│   ├── create_mc_database(output_dir / "mc_results.db")
│   ├── write_batch_meta(mc_config)
│   └── Generate parameter samples
│
├── 3. Pre-register all runs
│   └── write_run_registry(samples) # All runs marked "pending"
│
├── 4. Execute in parallel
│   ├── ProcessPoolExecutor(max_workers=mc_config.n_workers)
│   ├── Submit execute_single_run() for each sample
│   └── Collect futures as they complete
│
├── 5. Process results (serial)
│   ├── For each completed run:
│   │   ├── update_run_status()
│   │   ├── write_run_summary() (if success)
│   │   └── write_time_series() (if success)
│   └── For each failed run:
│       ├── update_run_status(status="failed")
│       └── write_batch_error()
│
└── 6. Finalize
    ├── update_batch_status("complete" or "partial")
    ├── Print summary
    └── Return path to results database
```

### 2. Parameter Mapping

Map Monte Carlo parameters to FVSSimulationConfig:

```python
MC_TO_FVS_PARAM_MAP = {
    # Management parameters
    "thin_q_factor": "thin_q_factor",
    "thin_residual_ba": "thin_residual_ba",
    "thin_trigger_ba": "thin_trigger_ba",
    "min_harvest_volume": "min_harvest_volume",
    "thin_min_dbh": "thin_min_dbh",
    "thin_max_dbh": "thin_max_dbh",
    # Monte Carlo-specific parameters (Phase 3)
    "mortality_multiplier": "mortality_multiplier",
    "enable_calibration": "enable_calibration",
    "fvs_random_seed": "fvs_random_seed",
}
```

### 3. Output Directory Structure

```
output_dir/
├── mc_results.db           # Main results database
├── run_0000/               # Per-run FVS outputs
│   ├── STAND_99/
│   ├── STAND_100/
│   └── ...
├── run_0001/
├── run_0002/
└── ...
```

### 4. Error Handling

- **Worker exception:** Catch in future.result(), log error, mark run as failed
- **All runs fail:** Raise RuntimeError with summary
- **Partial success:** Complete with "partial" status, report success rate
- **Keyboard interrupt:** Graceful shutdown, save completed results

### 5. Progress Reporting

```python
# Default progress output
[12/100] Run 0011 complete (0.8s) - 92 successful, 0 failed
[13/100] Run 0012 complete (0.7s) - 93 successful, 0 failed
...
```

---

## Validation Strategy

### Unit Tests (`tests/test_monte_carlo_executor.py`)

| Test | Description |
|------|-------------|
| `test_execute_single_run_success` | Mock FVS run, verify summary extraction |
| `test_execute_single_run_failure` | Simulate FVS error, verify error capture |
| `test_parameter_mapping` | Verify MC params map to FVS config correctly |
| `test_output_directory_structure` | Verify correct directory creation |
| `test_batch_with_single_worker` | Serial execution for debugging |
| `test_batch_with_multiple_workers` | Parallel execution basic test |
| `test_progress_callback` | Verify callback is called correctly |
| `test_partial_failure_handling` | Some runs succeed, some fail |

### Integration Test (add to `tests/test_monte_carlo_integration.py`)

```python
class TestFullBatch:
    def test_small_monte_carlo_batch(self, tmp_path):
        """
        Integration test: Run 5 samples with 2 workers on Section 6 data.
        Verify database is populated correctly.
        """
        # Use small batch for speed
        mc_config = MonteCarloConfig(
            batch_seed=42,
            n_samples=5,
            n_workers=2,
            plot_ids=[99, 100],  # Just 2 stands for speed
            parameter_specs=[
                UniformParameterSpec("mortality_multiplier", 0.8, 1.2),
            ],
            base_fvs_config={
                "num_years": 20,  # Short projection
                "cycle_length": 10,
            },
        )
        
        results_db = run_monte_carlo_batch(mc_config, stands, trees, tmp_path)
        
        # Verify database contents
        registry, summary, ts = load_mc_results(results_db)
        assert len(registry) == 5  # 5 runs
        assert len(summary) == 5  # All succeeded
        assert len(ts) > 0  # Time series populated
```

---

## Risk/Backout Notes

### Risks

1. **ProcessPool overhead:** Spawning processes has ~100ms overhead per run. For very short FVS runs (<1s), consider ThreadPoolExecutor instead.
   - *Mitigation:* FVS runs typically take 2-5s, so process overhead is acceptable.

2. **Memory pressure:** With many workers, each loading full stands/trees DataFrames.
   - *Mitigation:* DataFrames are ~10MB; even 16 workers = 160MB, acceptable on modern systems.

3. **SQLite concurrency:** Writing results from parallel workers.
   - *Mitigation:* Design already uses serial writes after parallel runs complete.

4. **Orphan FVS processes:** If main process crashes, child FVS processes may hang.
   - *Mitigation:* Use `with ProcessPoolExecutor() as executor:` context manager for cleanup.

### Backout

If Phase 5 causes issues:
1. Remove `executor.py` and its tests
2. Remove exports from `__init__.py`
3. All previous phases remain functional (database, config, extraction all work independently)

---

## Implementation Order

1. **Create `executor.py` skeleton** with function signatures and docstrings
2. **Implement `execute_single_run()`** - the worker function
3. **Implement `run_monte_carlo_batch()`** - the orchestrator
4. **Write unit tests** mocking FVS runs for fast testing
5. **Write integration test** with real FVS (small batch)
6. **Update `__init__.py`** to export new functions

---

## Estimated Effort

| Task | Hours |
|------|-------|
| executor.py skeleton | 0.5 |
| execute_single_run() | 1.5 |
| run_monte_carlo_batch() | 2.0 |
| Unit tests | 1.5 |
| Integration test | 0.5 |
| Documentation & cleanup | 0.5 |
| **Total** | **6.5** |

---

## Success Criteria

- [ ] `run_monte_carlo_batch()` executes N samples across M stands in parallel
- [ ] Results database contains batch_meta, run_registry, run_summary, time_series
- [ ] Failed runs are logged to MC_BatchErrors table
- [ ] Progress is reported during execution
- [ ] Unit tests pass without running actual FVS
- [ ] Integration test passes with real FVS (small batch)
- [ ] All 93+ existing tests still pass
