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
  output DB, no collisions, failures reported per task. Runs FVS via
  `--keywordfile=` and treats exit 0/10/20 as success (see run-method note below).
- **R workflows** in `scripts/r_workflow/` (**verified end-to-end locally**): a
  batch track (`build_input_db.R` writes the inventory CSVs to `FVS_Data.db`;
  `generate_keyfiles.R` templates database-style keyword files via
  `rFVS::fvsMakeKeyFile` + a manifest → the `cluster/` batch) and an interactive
  track (`project_stand.R`, rFVS `fvsInteractRun`, in-memory harvest). 296 stands
  → DB → keyfiles → 0-failure batch → populated `FVSOut.db`.
- **Python tooling is a real uv project** (`pyproject.toml` rewritten from a stray
  ML template to fvs_tools' actual deps + `uv.lock`); `uv run pytest` green
  (103 passed). Gives the Python side the same frozen-lock reproducibility renv
  gives R.
- **Smoke test stamps the FVS engine version** (parses the `RV:` banner) and is
  cross-image (fvsOL guards self-skip where fvsOL is absent, e.g. the cluster
  image), so one gate works in both deliverable images.

**Authored this session, PENDING BUILD VALIDATION** (the dev container has no
container runtime, so these were inspection-verified only — build them on a
podman/docker host, e.g. `ENGINE=podman bash scripts/build_images.sh`, or via the
first CI run, before relying on them):

- **Consolidated `docker/Dockerfile`** (replaces `Dockerfile.fvs` +
  `Dockerfile.webgui`): one common base `fvs-r-base` (FVS + R + renv pkgs + rFVS)
  with `webgui` (+ fvsOL/Shiny) and `cluster` (FVS + R + rFVS) targets. Hybrid FVS
  provenance via `--build-arg FVS_BASE=source` (default, compiles from
  `vendor/fvs`) or `ghcr` (bases off `usfs-fvs:FS2026.1` — the GHCR copy path is
  the one unverified piece, see the NOTE in the file).
- **CI** (`.github/workflows/ci.yaml`): a `python` job (uv sync + pytest) and an
  `images` job that runs `scripts/build_images.sh` (build webgui+cluster + in-image
  smoke test) — so "CI green" == "builds + works on the lab PC".

## Key files

| Area | Files |
| --- | --- |
| Dev image / setup | `Dockerfile` (devcontainer; dev sibling of the common base), `.devcontainer/devcontainer.json`, `.devcontainer/postCreate.sh` |
| Deliverable images | `docker/Dockerfile` (one multi-target file: `fvs-r-base` → `webgui`, `cluster`) |
| Image build / CI | `scripts/build_images.sh` (portable docker/podman build + in-image smoke test), `.github/workflows/ci.yaml` |
| Python tooling | `pyproject.toml` + `uv.lock` (uv project for `src/fvs_tools`), `tests/` |
| R env pin | `renv.lock`, `.Rprofile`, `renv/` |
| fvsOL/rFVS patches | `patches/*.patch` + `scripts/apply_fvsol_patch.sh` |
| FVS build | `scripts/build_fvs.sh` (wraps `vendor/fvs-build` Meson overlay) |
| WebGUI launch | `scripts/run_webgui.sh`, `docker/webgui-app.R` |
| Regression gate | `scripts/smoke_test.R` |
| HPC batch | `cluster/` (`fvs_run_one.sh`, `fvs_array.sbatch`, `run_local.sh`, `build_sif.sh`, `README.md`) |
| R workflows | `scripts/r_workflow/` — batch track (`build_input_db.R` + `generate_keyfiles.R` → `cluster/`) and interactive track (`project_stand.R`, rFVS); reuses the course reference `scripts/reference_scripts/*.R` |
| Docs | `docs/HELLGATE_FVS.md` (HPC approach), this file |
| Submodules | `vendor/fvs` (USDA FVS source), `vendor/fvs-build` (Meson build), `vendor/fvs-interface` (rFVS + fvsOL) |

## Container architecture & where builds run (end state)

One **common base** (`fvs-r-base` = FVS engine + R + renv-pinned packages + rFVS)
that both shipped images derive from, so a keyword file / R workflow validated in
one runs identically in the other:

- **`fvs-webgui:<variant>`** = `fvs-r-base` + fvsOL + Shiny + `webgui-app.R` —
  interactive GUI (port 3838).
- **`fvs-engine:<variant>`** = the `cluster` target (`fvs-r-base` as-is) — the HPC
  deliverable; carries R + rFVS so the R workflows run **on Hellgate**, not just
  the bare CLI. Converted to the Hellgate `.sif` (`build_sif.sh` or
  `apptainer pull` from a registry).

The **devcontainer** (`Dockerfile`) is a **dev-only sibling**, not shipped and not
nested inside the others: same `rocker/r2u:24.04` base, same `renv.lock`, same
`vendor/fvs` source + `build_fvs.sh`, but FVS is compiled into it by `postCreate`
(not baked) so devs can rebuild the engine without rebuilding the image. (It could
later be folded into `docker/Dockerfile` as a `dev` target; kept separate for now.)

**Where builds run:** (1) **CI / a workstation (lab PC)** build the images via the
*same* `scripts/build_images.sh` (docker in CI, `ENGINE=podman` on the lab PC) —
NOT inside the devcontainer (no runtime there). (2) the **devcontainer** is built
by VS Code on the host. (3) the **`.sif`** is `apptainer pull`ed from a registry on
Hellgate, or `build_sif.sh` + scp. **FVS provenance is hybrid**: source-compiled by
default, GHCR-based via `FVS_BASE=ghcr`.

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
- **Run method depends on keyword-file style (verified 2026-05-28).**
  `FVSie --keywordfile=x.key` works for **all** keyword files — FVS derives the
  aux filenames (`.tre`/`.out`/`.trl`) from the keyword base name and runs
  non-interactively; this is what the batch runner uses. `echo x.key | FVSie`
  (stdin) works **only** for self-contained *database-style* keyword files
  (`DSNin`/`StandSQL`/`TreeSQL` + `DSNOut`); for *flat-file* keyword files
  (`.key` + separate `.tre`) stdin drops FVS into interactive filename prompting
  and fails. **`STOP 20` = normal completion** (and `STOP 10` = with-warnings);
  both are success — the runner treats exit 0/10/20 as success. Data/keyword
  problems are logged to the `FVS_Error` table, not the exit code. Outputs land
  in the cwd → each run needs its own dir.
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

1. **Forester config-generation (Path 1) — BUILT.** `scripts/r_workflow/`: R as a
   keyword-file *generator*. `build_input_db.R` writes the inventory CSVs to an
   FVS `FVS_Data.db` (FVS_StandInit/FVS_TreeInit); `generate_keyfiles.R` templates
   one *database-style* keyword file per stand via **`rFVS::fvsMakeKeyFile()`**
   (FVS's own generator, reused — not reinvented) + a manifest, run via the
   existing `cluster/` batch. Verified end-to-end locally (296 stands → DB →
   keyfiles → 0-failure batch → populated `FVSOut.db`). To sweep Event-Monitor
   thresholds/treatments (the Monte Carlo pattern) pass extra records via
   `fvsMakeKeyFile(moreKeywords=...)`; further building blocks in the Python
   `src/fvs_tools/monte_carlo/` and microfvs's KCP library.
2. **rFVS interactive (Path 2) — single-stand BUILT.** `scripts/r_workflow/project_stand.R`
   drives FVS as a library via `fvsLoad` + `fvsInteractRun`, harvesting per-cycle
   tree lists + summary into R in-memory (verified on CARB_2). A *parallel* rFVS
   batch (R+rFVS+`.so` image, per-task `fvsInteractRun` driver) is only needed if
   between-cycle R logic must run at HPC scale — the reference workflow doesn't,
   so it's deferred until a concrete need appears.
3. **Build validation (next action, needs a container runtime).** The
   consolidated `docker/Dockerfile` + CI were authored but not built (no runtime
   in the dev container). On the lab PC: `ENGINE=podman bash scripts/build_images.sh`
   (builds `webgui` + `cluster`, runs the in-image smoke test). The one piece to
   confirm is the `FVS_BASE=ghcr` copy path against the real `usfs-fvs` image; the
   default `FVS_BASE=source` mirrors the previously-green from-source builds.
4. **Hellgate validation (needs cluster access).** See the "[confirm on
   cluster]" list in `docs/HELLGATE_FVS.md`: partitions/limits, login-node
   network egress, fakeroot, modules, BeeGFS paths, real `.sif` under Apptainer.
5. **Prune for final product.** Strip data artifacts and exploratory/course
   files (Monte Carlo notebooks etc. are kept for now as workflow reference).

## How to resume in a fresh session

1. Read this file + `docs/HELLGATE_FVS.md` + `cluster/README.md`.
2. `git log --oneline` on `fvs-container-build` for the change history.
3. Local sanity: `Rscript scripts/smoke_test.R`; WebGUI: `bash scripts/run_webgui.sh`
   (port 3838); HPC dry-run: build a manifest and run `cluster/run_local.sh`.
4. Open questions are the Hellgate specifics (above) and which forester path
   (Event Monitor vs rFVS) the target logic needs.
