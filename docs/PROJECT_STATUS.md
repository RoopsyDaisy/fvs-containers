# FVS container project — status, decisions & roadmap

Handoff doc so this work can be resumed in a fresh session without losing
context. Branch: **`fvs-container-build`**.

## What this project is

Reproducible **Forest Vegetation Simulator (FVS)** containers for a University
of Montana forestry course (FORS591). Two deliverables share one FVS engine:

1. **WebGUI devcontainer** — the fvsOL Shiny app + FVS, for interactive
   single-stand exploration (port 3838).
2. **CLI FVS for HPC** — for the lecturer to run many keyword files in parallel
   on **Hellgate** (UM's SLURM + Apptainer cluster). This is the deliverable the
   lecturer said they'd actually use.

## Status — done (verified)

All committed on `fvs-container-build` (`0284894` → `8dbf567`):

- **Reproducible R environment**: `renv` + a **dated Posit Package Manager (P3M)
  binary snapshot** (`.../noble/2026-05-27`) replaces rocker/r2u rolling-latest.
  `renv.lock` pins fvsOL's full dependency closure; native system libs installed
  via apt (derived with `pak::pkg_sysreqs`).
- **fvsOL/rFVS source patches** (carried in `patches/`, applied by
  `scripts/apply_fvsol_patch.sh`): RSQLite temp-table writes, `fs` attach,
  `StagedInstall: no`, rFVS `Encoding: UTF-8`.
- **FVS engine via fvs-build**: `vendor/fvs-build` (Meson overlay submodule)
  compiles FVS from `vendor/fvs` (USDA source, tag FS2026.1), producing the CLI
  `FVS<v>` **and** the self-contained embedder `FVS<v>.so` that rFVS loads.
  `scripts/build_fvs.sh` is now a thin wrapper over it.
- **Smoke test** (`scripts/smoke_test.R`) guards the dependency-drift bugs; runs
  at the end of `postCreate`.
- **Clean-from-scratch devcontainer rebuild verified green** (renv restore + FVS
  build + fvsOL/rFVS install + smoke test).
- **HPC batch runner** in `cluster/` (manifest-driven SLURM array), **validated
  locally**: a batch of keyword files each runs in an isolated dir with its own
  output DB, no collisions, failures reported per task.

## Key files

| Area | Files |
| --- | --- |
| Dev image / setup | `Dockerfile`, `.devcontainer/devcontainer.json`, `.devcontainer/postCreate.sh` |
| Deliverable images | `docker/Dockerfile.webgui` (WebGUI), `docker/Dockerfile.fvs` (slim CLI engine) |
| R env pin | `renv.lock`, `.Rprofile`, `renv/` |
| fvsOL/rFVS patches | `patches/*.patch` + `scripts/apply_fvsol_patch.sh` |
| FVS build | `scripts/build_fvs.sh` (wraps `vendor/fvs-build` Meson overlay) |
| WebGUI launch | `scripts/run_webgui.sh`, `docker/webgui-app.R` |
| Regression gate | `scripts/smoke_test.R` |
| HPC batch | `cluster/` (`fvs_run_one.sh`, `fvs_array.sbatch`, `run_local.sh`, `build_sif.sh`, `README.md`) |
| Docs | `docs/HELLGATE_FVS.md` (HPC approach), this file |
| Submodules | `vendor/fvs` (USDA FVS source), `vendor/fvs-build` (Meson build), `vendor/fvs-interface` (rFVS + fvsOL) |

## Decisions & non-obvious facts (would waste time to rediscover)

- **fvsOL ships incompatible with its contemporary CRAN packages** → pinning
  alone doesn't fix runtime breakage; source patches are also required.
  (RSQLite 3.53.x rejects `dbWriteTable(conn, DBI::SQL("temp.X"), …)` → use
  `temporary=TRUE`; fvsOL calls `fs::dir_exists` by bare name → `library(fs)`.)
- **bspm must be disabled** for renv/install.packages in the r2u image (it hooks
  install and fails on missing D-Bus). Done by neutralizing `bspm::enable()` in
  `/etc/R/Rprofile.site`.
- **renv.lock date must serve the locked versions.** The lock was hydrated from
  rolling-latest packages, so the P3M snapshot date has to be ≥ when those were
  published (hence 2026-05-27, not an older date) or a clean restore 404s.
- **fvsOL needs `StagedInstall: no`** (it bakes an abs path during build, so R's
  staged install fails). Only surfaces on a real `renv::install`, not when
  hydrated/copied.
- **git identity is host-delegated**: VS Code copies the host (`~/.gitconfig`)
  into the container at creation. The Fedora host now has it set; in-container
  commits before a rebuild used `git -c user.name=… -c user.email=…`.
- **FVS CLI reads the keyword *filename* on stdin** (`echo x.key | FVSie`), NOT
  `--keywordfile=`. (rFVS's `fvsSetCmdLine("--keywordfile=…")` is the library
  path, which does accept the flag.) FVS exits 0 on success, non-zero (e.g. 10,
  20) on data/keyword errors. Outputs land in the cwd → each run needs its own dir.
- **Apptainer/SLURM can't be faithfully tested in the dev container** (no
  `/dev/fuse` → no real `.sif`; user namespaces *are* available). Real cluster
  validation is Hellgate-only.

## FVS modeling capabilities — basis for the forester workflow

Two distinct ways to do conditional "logic between years":

- **(A) Event Monitor** — FVS's native in-keyword-file engine (`COMPUTE`,
  `IF`/`THEN`, condition-triggered activities). "When a stand metric crosses a
  threshold, apply treatment X." Runs inside FVS → **fully compatible with the
  CLI batch** (it's just richer keyword files). This is what the fvsOL GUI
  exposes (Components → Event Monitor / Keywords).
- **(B) rFVS stepping** — R drives FVS as a library, running arbitrary R between
  cycles. Driver: **`rFVS::fvsInteractRun`** ([vendor/fvs-interface/rFVS/R/fvsInteractRun.R](../vendor/fvs-interface/rFVS/R/fvsInteractRun.R)),
  which runs R code blocks at named per-cycle stop points (`BeforeEM1`,
  `AfterEM1`, `BeforeEM2`, `AfterEM2`, `BeforeAdd`, `BeforeEstab`, `SimEnd`).
  State read/modify API: `fvsGetSummary`, `fvsGetTreeAttrs`,
  `fvsGetEventMonitorVariables`, `fvsSetTreeAttr`, `fvsCutNow`, `fvsAddActivity`,
  `fvsAddTrees`. Needs the `.so` + R (not the plain CLI). We already build the
  `.so`; a batch needs an R+rFVS image (headless WebGUI image).

## Roadmap / plan

1. **Forester config-generation (Path 1, most likely the real need).** R as a
   keyword-file *generator*: template N keyword files (varying Event Monitor
   thresholds / treatments — the Monte Carlo pattern), run via the existing CLI
   batch. Mine the Monte Carlo notebooks (`notebooks/`, `scripts/*monte*`,
   `scripts/run_fvs_lubrecht_plot48.py`) and microfvs's KCP treatment library
   (`github.com/Vibrant-Planet-Open-Science/microfvs`) for building blocks.
2. **rFVS-driven batch (Path 2, if true in-sim R is needed).** Build an
   R+rFVS+`.so` batch image; per-task R driver based on `fvsInteractRun`.
   Decide Path 1 vs 2 from a concrete forester example (threshold→treatment ⇒
   Path 1; must call external code mid-run ⇒ Path 2).
3. **Hellgate validation (needs cluster access).** See the "[confirm on
   cluster]" list in `docs/HELLGATE_FVS.md`: partitions/limits, login-node
   network egress, fakeroot, modules, BeeGFS paths, real `.sif` under Apptainer.
4. **Prune for final product.** Strip data artifacts and exploratory/course
   files (Monte Carlo notebooks etc. are kept for now as workflow reference).

## How to resume in a fresh session

1. Read this file + `docs/HELLGATE_FVS.md` + `cluster/README.md`.
2. `git log --oneline` on `fvs-container-build` for the change history.
3. Local sanity: `Rscript scripts/smoke_test.R`; WebGUI: `bash scripts/run_webgui.sh`
   (port 3838); HPC dry-run: build a manifest and run `cluster/run_local.sh`.
4. Open questions are the Hellgate specifics (above) and which forester path
   (Event Monitor vs rFVS) the target logic needs.
