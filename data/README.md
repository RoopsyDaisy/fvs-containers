# `data/` — inventory inputs for the R workflows

The R workflows under [`scripts/r_workflow/`](../scripts/r_workflow/) read a forest
inventory from two CSV files in this directory. **These files are not committed**
(they're gitignored — see the repo root `.gitignore`), so a fresh clone must
supply them before the R tracks will run. This README is the data *contract*.

> If a workflow stops with *"Required input not found … see data/README.md"*,
> you're here because one of these files is missing.

## Required files

| File | FVS table it becomes | Read by |
|------|----------------------|---------|
| `FVS_Lubrecht_2023_FVS_StandInit.csv` | `FVS_StandInit` | all four R-workflow scripts |
| `FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv` | `FVS_TreeInit` | `build_input_db.R`, `project_stand.R` |

Notes on the names:
- The tree file's doubled `FVS_FVS_` is intentional — it's the exact filename the
  scripts expect. Match it (or change the constants in
  [`scripts/r_workflow/data_paths.R`](../scripts/r_workflow/data_paths.R)).
- **Encoding:** the scripts read these as `UTF-8-BOM` (a UTF-8 CSV with a leading
  byte-order mark, i.e. the default export from Excel / the FVS database tools).
- Column **names must match the FVS schema** — `build_input_db.R` writes them
  verbatim into the `FVS_StandInit` / `FVS_TreeInit` SQLite tables that FVS reads
  via its Database Extension (`DSNin`/`StandSQL`/`TreeSQL`). No remapping happens.

## Columns the repo's scripts actually rely on

These are the FVS-standard StandInit/TreeInit exports; the interactive driver's
flat-file writer (`scripts/reference_scripts/fvs_keyword_file_functions.R`) uses
the subset below, so a fixture must at least carry these:

**StandInit** — `STAND_ID`, `INV_YEAR`, `FOREST`, `PV_CODE`, `AGE`, `ASPECT`,
`SLOPE`, `ELEVFT`, `SITE_SPECIES`, `SITE_INDEX`, `NUM_PLOTS`, `DG_TRANS`,
`DG_MEASURE`, `HTG_TRANS`, `HTG_MEASURE`, `MORT_MEASURE`.
(`ASPECT`/`SLOPE`/`ELEVFT`/`FOREST` may be `NA`; the writer fills variant defaults.)

**TreeInit** — `STAND_ID`, `PLOT_ID`, `TREE_ID`, `TREE_COUNT`, `HISTORY`,
`SPECIES` (FIA code), `DIAMETER`, `DG`, `HT`, `HTTOPK`, `HTG`, `CRRATIO`,
`TOPOCODE`, `AGE`. (`project_stand.R` regenerates `fvs.TREE_ID` itself.)

The database track (`build_input_db.R` → `generate_keyfiles.R` →
`rFVS::fvsMakeKeyFile`) only requires that the columns be a valid
`FVS_StandInit`/`FVS_TreeInit` schema and that `STAND_ID` resolves the stands you
ask for; FVS reads the rest directly from the database.

## How to obtain the data

- **The course dataset.** The original inputs are the University of Montana
  **Lubrecht Experimental Forest 2023** inventory (FORS591). Obtain them from the
  course materials / lecturer and export the StandInit and TreeInit tables to the
  two CSV filenames above.
- **A stand-in for smoke-testing the plumbing.** Any FVS `StandInit`/`TreeInit`
  database (e.g. an FVS example/training dataset, or the data fvsOL bundles) can
  be exported to these two CSVs to exercise the workflows. Pick stand IDs that
  exist in your data when you pass `STANDS=...` (the script defaults — `CARB_2`,
  `CARB_3`, `CARB_4` — are Lubrecht stand IDs).

## Committing a fixture (maintainers)

`*.csv` and `data/*` are gitignored, so a deliberate fixture must be force-added:

```bash
git add -f data/FVS_Lubrecht_2023_FVS_StandInit.csv \
            data/FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv
```

Only commit data you have the right to redistribute, and prefer a **small**
sample. Validate it end-to-end against the FVS engine first (`build_input_db.R`
→ `generate_keyfiles.R` → `cluster/run_local.sh`) — a fixture with the wrong or
missing columns is worse than none.
</content>
