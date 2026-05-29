# R workflows for FVS

R-based ways to drive the Forest Vegetation Simulator (FVS), using the **same FVS
engine** as the WebGUI (`.devcontainer/fvs-bin` here; the `cluster` engine image
on Hellgate). Because the engine is identical, a keyword file validated in the GUI
or here runs the same on the HPC batch.

There are two tracks, for two different needs:

| Track | Script(s) | When | How FVS is run |
| --- | --- | --- | --- |
| **Batch / scale** | `build_input_db.R`, `generate_keyfiles.R` | many stands or scenarios, run in parallel | generates keyword files → the file-based batch (`cluster/`) runs them |
| **Interactive / in-sim R** | `project_stand.R` | you need R logic *between* FVS cycles, or per-cycle results in R | rFVS loads FVS as a library and steps through it |

Both reuse FVS's own R code rather than reinventing it: the batch generator is
`rFVS::fvsMakeKeyFile()`; the interactive driver is `rFVS::fvsInteractRun()`; the
flat-file writer is the course reference `write.FVSfiles()`
([../reference_scripts/fvs_keyword_file_functions.R](../reference_scripts/fvs_keyword_file_functions.R)).

## Track A — batch (R generates keyword files → file-based runner)

R builds an FVS input database from the inventory CSVs, then templates one
*database-style* keyword file per stand (each reads its records from the shared
`FVS_Data.db` via `DSNin`/`StandSQL`/`TreeSQL`, writes to its own `FVSOut.db`).
The keyword files are plain inputs to the existing batch runner — see
[../../cluster/README.md](../../cluster/README.md) for the SLURM/Apptainer path on Hellgate.

```bash
# 1. inventory CSVs -> FVS_Data.db (FVS_StandInit + FVS_TreeInit tables)
Rscript scripts/r_workflow/build_input_db.R outputs/r_batch/FVS_Data.db all

# 2. one keyword file per stand + a keyfiles.txt manifest (55-year projection)
Rscript scripts/r_workflow/generate_keyfiles.R outputs/r_batch CARB_2,CARB_3,CARB_4 55

# 3. run the batch (locally; the same fvs_run_one.sh runs on the cluster)
FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT=$PWD/outputs/r_batch/FVS_Data.db \
  cluster/run_local.sh outputs/r_batch/keyfiles.txt outputs/r_runs
```

Results land in `outputs/r_runs/<STAND_ID>/FVSOut.db` (tables `FVS_Summary2`,
`FVS_Compute`, …). Use `STANDS=all` in step 2 to template every stand. To sweep a
treatment or Event-Monitor threshold across runs (the Monte Carlo pattern), pass
the extra keyword records through `fvsMakeKeyFile(moreKeywords=...)`.

## Track B — interactive (R drives FVS via rFVS)

For a single stand, generate a flat-file keyword + tree file, load the FVS shared
library, run it cycle-by-cycle, and pull per-cycle tree lists + the summary into R
in memory (no database). This is where you'd insert R logic that the keyword-file
Event Monitor can't express.

```bash
Rscript scripts/r_workflow/project_stand.R CARB_2 55
# -> outputs/r_project/CARB_2/{tree_list.csv,stand_summary.csv}
```

## Notes

- **Run method.** The batch runner invokes `FVS --keywordfile=name`, which works
  for both database-style and legacy flat-file keyword files (it derives the
  `.tre`/`.out`/`.trl` names from the keyword base name and runs non-interactively).
  Piping the keyword name on stdin (`echo name | FVS`) only works for
  database-self-contained keyword files; flat-file ones make FVS prompt for each
  filename interactively.
- **Exit codes.** FVS signals normal completion with `STOP 20` (and `STOP 10` for
  completed-with-warnings); both are success. The runner treats exit 0/10/20 as
  success. Per-stand data/keyword problems are logged to the `FVS_Error` table in
  the output DB, not the exit code.
- **Two keyword-file styles.** *Database-style* (what the GUI and
  `rFVS::fvsMakeKeyFile` produce) reads/writes via SQLite and feeds the batch.
  *Flat-file* (`write.FVSfiles`) pairs a `.key` with a `.tre` and suits the rFVS
  in-memory track.
