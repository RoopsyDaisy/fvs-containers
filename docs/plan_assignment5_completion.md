# Plan: Assignment 5 Completion & Future Scaling

## 1. Assessment of Current State

### Completed & Verified
- **Database Input**: `DSNin` works, replacing `TREELIST`.
- **Canopy Cover**: `COMPUTE` keyword with `SPMCDBH(7, ...)` works and outputs to `FVS_Compute`.
- **Basic Simulation**: `runner.py` and `batch.py` successfully execute runs.
- **Summary Output**: `FVS_Summary` table is parsed correctly.

### Gaps & Issues
- **Carbon Output**: `FVS_Carbon` table was missing in test runs despite `output_carbon=True`. Needs investigation (likely missing `FFE` activation or specific keyword placement).
- **Management Keywords**: No support yet for `MINHARV` or Q-factor thinning (`THINQ` / `THINAUTO`).
- **Harvest Outputs**: Need to verify where harvest volumes and stored carbon are reported.
- **Scenario Management**: Current system runs one config at a time. Need a way to define and run multiple scenarios (Base vs. Harv1) and compare them.

## 2. Implementation Plan

### Phase 1: Fix Carbon Output
- **Objective**: Ensure `FVS_Carbon` table is populated.
- **Action**:
    - Investigate if `FMIN` (Fire Management Input) is required to activate FFE.
    - Verify `CARBON` keyword placement (inside vs outside `DATABASE` block).
    - Run `test_db_input.py` until `FVS_Carbon` is present.

### Phase 2: Implement Management Keywords
- **Objective**: Support Part II requirements (Q-factor thinning, Min Harvest).
- **Action**:
    - Update `FVSSimulationConfig` to include management parameters:
        - `management_mode`: "none", "thinning_q"
        - `min_harvest_bf`: 4500
        - `thin_q_factor`: 2.0
        - `thin_residual_ba`: 65.0
        - `thin_trigger_ba`: 100.0
        - `thin_dbh_min`: 2.0
        - `thin_dbh_max`: 24.0
    - Update `keyword_builder.py` to generate:
        - `MINHARV` (must be before thinning keywords).
        - Conditional block (`IF` ... `THINQ` ... `ENDIF`) or `THINAUTO`.
        - *Note*: "Q-factor thinning... triggered by BA > 100... applied such that 65 BA retained" suggests `THINQ` or `THINAUTO` with `QFACTOR` and `RESID` parameters.
        - Syntax research needed for `THINQ` in FVSie.

### Phase 3: Harvest & Stored Carbon Outputs
- **Objective**: Extract harvest volume and stored carbon.
- **Action**:
    - **Harvest Volume**: Sum `RBdFt` (Removed Board Feet) from `FVS_Summary`.
    - **Stored Carbon**: Check `FVS_Carbon` for "Products" or "Removed" columns. If not present, check `FVS_HrvCarb` (Harvest Carbon) table.
    - Update `output_parser.py` to extract these metrics.

### Phase 4: Scenario & Comparison Framework
- **Objective**: Enable multi-scenario runs and comparison (Future Proofing).
- **Action**:
    - Create `Scenario` class (wraps `FVSSimulationConfig` + metadata).
    - Update `batch.py` to accept a list of Scenarios.
    - Create `comparison.py` module:
        - Load results from multiple scenarios.
        - Merge into a single DataFrame with `Scenario` column.
        - Generate comparison plots (e.g., BA over time by Scenario).

## 3. Execution Steps

1.  **Debug Carbon**: Fix `FVS_Carbon` generation.
2.  **Update Config**: Add management fields to `FVSSimulationConfig`.
3.  **Update Keywords**: Implement `build_management_keywords` in `keyword_builder.py`.
4.  **Update Parser**: Add harvest metrics to `output_parser.py`.
5.  **Run Part II**: Create "harv1" config and run.
6.  **Compare**: Generate comparison tables/plots.

## 4. Resources
- FVS Wiki/Docs for keyword syntax (`THINQ`, `MINHARV`).
- `FVS_Carbon` schema inspection.
