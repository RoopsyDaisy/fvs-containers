# Monte Carlo FVS Simulation Tool - Presentation Outline

Use this outline to generate a PowerPoint presentation about the Monte Carlo sampling framework for FVS forest growth simulations.

---

## Slide 1: Title Slide

**Title:** Introducing Monte Carlo Sampling for FVS Simulations  
**Subtitle:** Quantifying Uncertainty in Forest Growth Projections  

**Visual Instructions:** Create a hero image showing a "spaghetti plot" - approximately 100 overlaid line trajectories of total carbon (tons/acre) over 100 years. Each line represents one simulation with different parameter combinations. The lines should fan out over time showing increasing uncertainty. Use a forest green to blue color gradient. Include axis labels: X-axis "Year (2023-2123)", Y-axis "Total Carbon (tons/ac)".

---

## Slide 2: What is Monte Carlo Simulation?

**Title:** What is Monte Carlo Simulation?  

**Bullet Points:**
- Forest growth models have uncertain inputs (mortality rates, thinning thresholds, growth calibration)
- Exhaustively testing all parameter combinations is computationally impossible
- Monte Carlo sampling: randomly sample parameter combinations to estimate output distributions
- Run hundreds or thousands of simulations to build a statistical picture of outcomes

**Visual Instructions:** Create a simple flow diagram with 4 boxes connected by arrows:
1. "Input Parameters (with ranges)" → 
2. "Random Sampling" → 
3. "Many FVS Runs (100+)" → 
4. "Output Distribution"

Use icons: dice for sampling, tree for FVS, bell curve for distribution.

---

## Slide 3: Why Use Monte Carlo with FVS?

**Title:** Why Monte Carlo for Forest Management?  

**Content with Icons:**
- 📊 **Uncertainty Quantification:** How confident are we in carbon projections given unknown future conditions?
- ⚠️ **Risk Assessment:** What's the probability of canopy cover falling below regulatory thresholds?
- 🎯 **Robust Optimization:** Find management strategies that perform well across a range of conditions
- 🔍 **Sensitivity Analysis:** Which parameters have the biggest impact on outcomes?

**Visual Instructions:** Create a side-by-side comparison:
- Left panel: Single line labeled "Deterministic Projection" 
- Right panel: Fan of ~50 lines with shaded confidence band labeled "Monte Carlo Ensemble"

Caption: "Single projections hide uncertainty; Monte Carlo reveals it"

---

## Slide 4: Example Parameter Ranges

**Title:** Configuring Parameter Uncertainty  

**Content:** Display this table of the 5 parameters being varied:

| Parameter | Baseline | Range | Description |
|-----------|----------|-------|-------------|
| thin_q_factor | 2.0 | 1.5 - 2.5 | Thinning intensity (BDq method) |
| thin_residual_ba | 65 | 50 - 75 ft²/ac | Target basal area after thinning |
| thin_trigger_ba | 100 | 95 - 125 ft²/ac | BA threshold to trigger harvest |
| mortality_multiplier | 1.0 | 0.8 - 1.2 | Scales background mortality ±20% |
| min_harvest_volume | 4500 | 3500 - 5500 bdft/ac | Economic harvest threshold |

**Visual Instructions:** Show a code snippet in a styled code block:
```python
UniformParameterSpec("thin_q_factor", 1.5, 2.5),
UniformParameterSpec("mortality_multiplier", 0.8, 1.2),
```

Use a clean, professional table design with alternating row colors.

---

## Slide 5: Output Metrics

**Title:** What We Measure  

**Two-Column Layout:**

**Left Column - Per-Simulation Summary Metrics:**
- Final values: final_total_carbon, final_canopy_cover
- Extremes: min_canopy_cover (bottleneck across all years)
- Cumulative: cumulative_harvest_bdft (total board feet harvested)
- Averages: avg_carbon_stock (mean over projection period)

**Right Column - Per-Timestep Outputs:**
- Year-by-year carbon pools
- Annual canopy cover percentage
- Basal area trajectory
- Cumulative harvest over time

**Visual Instructions:** Include a small example table showing 3-4 rows of summary data with columns: run_id, final_total_carbon, min_canopy_cover, cumulative_harvest_bdft. Use realistic values like: (1, 45.2, 52.3, 12500), (2, 48.1, 48.7, 15200), etc.

---

## Slide 6: Batch Configuration

**Title:** Monte Carlo Batch Setup  

**Content:** Show this configuration code block prominently:

```python
mc_config = MonteCarloConfig(
    batch_seed=42,           # Reproducible randomness
    n_samples=100,           # Number of parameter combinations
    n_workers=20,            # Parallel execution
    parameter_specs=[
        UniformParameterSpec("thin_q_factor", 1.5, 2.5),
        UniformParameterSpec("thin_residual_ba", 50.0, 75.0),
        UniformParameterSpec("thin_trigger_ba", 95.0, 125.0),
        UniformParameterSpec("mortality_multiplier", 0.8, 1.2),
        UniformParameterSpec("min_harvest_volume", 3500.0, 5500.0),
    ],
    base_config=base_config,
)
```

**Visual Instructions:** Below the code, show a screenshot or table representation of the "Run Registry" - a table with columns: run_id, thin_q_factor, thin_residual_ba, mortality_multiplier showing 4-5 example rows with sampled values.

---

## Slide 7: Results Database Schema

**Title:** Structured Output Storage  

**Content:** All results stored in SQLite database with 5 tables:

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| MC_BatchMeta | Batch configuration | batch_id, n_samples, n_workers, status |
| MC_RunRegistry | Sampled parameters per run | run_id, thin_q_factor, mortality_multiplier, ... |
| MC_RunSummary | Aggregated outcomes per run | final_total_carbon, min_canopy_cover, cumulative_harvest |
| MC_TimeSeries | Year-by-year trajectories | year, total_carbon, canopy_cover_pct, ba |
| MC_BatchErrors | Failed run diagnostics | run_id, error_msg, timestamp |

**Visual Instructions:** Create a simple entity-relationship style diagram showing the 5 tables as boxes with key relationships:
- BatchMeta (1) → RunRegistry (many)
- RunRegistry (1) → RunSummary (1)
- RunRegistry (1) → TimeSeries (many years)
- BatchMeta (1) → BatchErrors (many)

---

## Slide 8: Visualizing Variation - Trajectory Plots

**Title:** Visualizing Simulation Uncertainty  

**Two-Panel Layout:**

**Left Panel - Spaghetti Plot:**
- All 100 simulation runs overlaid
- Each line is a different color (viridis colormap)
- Shows full range of possible outcomes
- Caption: "Individual Trajectories"

**Right Panel - Percentile Band Plot:**
- Bold line for mean trajectory
- Shaded band showing 5th to 95th percentile
- Caption: "Mean with 90% Confidence Band"

**Visual Instructions:** Create two side-by-side time series plots for "Total Carbon (tons/ac)" vs "Year". Left plot has many thin overlapping lines. Right plot has one thick line with a shaded region around it. Use consistent axis scales and professional styling.

---

## Slide 9: Parameter → Outcome Relationships

**Title:** Linking Parameters to Outcomes  

**Bullet Points:**
- Join input registry with output summary to analyze relationships
- Scatter plots reveal parameter sensitivity
- Identify which parameters most influence key outcomes

**Example Insights:**
- Higher mortality_multiplier → Lower final carbon stocks
- Higher thin_trigger_ba → More cumulative harvest
- thin_q_factor shows nonlinear effects on canopy cover

**Visual Instructions:** Create a 2x2 grid of scatter plots:
1. mortality_multiplier (x) vs final_total_carbon (y)
2. thin_q_factor (x) vs min_canopy_cover (y)
3. thin_trigger_ba (x) vs cumulative_harvest_bdft (y)
4. thin_residual_ba (x) vs final_total_carbon (y)

Each plot should show ~100 points with a trend line. Use a consistent color scheme.

---

## Slide 10: Future Development

**Title:** Roadmap  

**Planned Enhancements:**
- 🌲 Additional parameter support (regeneration, site index variation)
- 🌡️ Climate scenario integration
- ⚙️ Macro-level configuration (treatment timing sequences, management regimes)
- 🔗 Integration with optimization frameworks
- 📊 Enhanced visualization dashboard
- 🗺️ Spatial analysis across stand mosaics

**Visual Instructions:** Create a simple horizontal roadmap with 3 phases:
- Phase 1 (Complete): "Core MC Framework"
- Phase 2 (In Progress): "Extended Parameters"
- Phase 3 (Planned): "Optimization & Visualization"

Use checkmarks, progress circles, and future icons appropriately.

---

## Slide 11: How to Use It

**Title:** Getting Started  

**Two-Column Layout:**

**Left Column - Available Now (Green checkmarks):**
- ✅ Jake built Linux version of FVS (FVSie variant)
- ✅ All code open source on GitHub
- ✅ Python library with clean API
- ✅ Documentation and example notebooks
- ✅ Devcontainer for reproducible environment

**Right Column - Caveats (Orange warnings):**
- ⚠️ Research tool - limited ongoing support expected
- ⚠️ Requires Python and command-line familiarity
- ⚠️ Linux environment recommended
- ⚠️ FVS expertise helpful for interpretation

**Visual Instructions:** Include a stylized GitHub logo or repository card. Optionally add a QR code placeholder labeled "Scan for Repository". Keep the tone welcoming but realistic about support expectations.

---

## Appendix: Available Visualizations

The following plots are already generated in the MCResults.ipynb notebook and can be exported as images:

| Slide | Notebook Location | Description |
|-------|-------------------|-------------|
| Slide 1 | Cell 21 | 4-panel spaghetti plots (carbon, canopy, BA, harvest) |
| Slide 4 | Cell 12 | Parameter distribution histograms |
| Slide 5 | Cell 16 | Outcome metric distribution histograms |
| Slide 6 | Cell 11 | Run registry table display |
| Slide 7 | Cell 8 | Database schema inspection output |
| Slide 8 | Cells 21 + 22 | Spaghetti plots and percentile band plots |
| Slide 9 | Cell 19 | Parameter vs outcome scatter plot |

---

## Design Guidelines

- **Color Palette:** Use forest greens, earth tones, and professional blues
- **Fonts:** Clean sans-serif (Calibri, Arial, or similar)
- **Code Blocks:** Use monospace font with syntax highlighting
- **Charts:** Consistent axis labels, legends, and grid lines
- **Icons:** Use simple, professional iconography for bullet points
- **Images:** High-resolution exports from matplotlib (300 DPI recommended)

---

## Key Messages to Emphasize

1. **Uncertainty is inherent** - Single projections are misleading
2. **Monte Carlo is practical** - Modern computing makes it feasible
3. **Results are actionable** - Risk assessment, sensitivity analysis, robust planning
4. **Tool is accessible** - Open source, documented, containerized
5. **Research-grade** - Powerful but requires expertise to use effectively
