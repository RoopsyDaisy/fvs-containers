# FVS container project — status, decisions & roadmap

Handoff doc so this work can be resumed in a fresh session without losing
context.

> **Current state (updated 2026-05-29).** Several items below were written while
> work was in flight and have since landed — read this banner first, then treat
> the rest as historical narrative:
> - **Repo renamed** `fors591` → `fvs-containers` (done; the old dev branch
>   `fvs-container-build` referenced throughout no longer exists — `main` is the
>   trunk).
> - **GHCR publish is LIVE**, not "inert": `.github/workflows/publish.yaml` builds
>   + pushes on `main`/`v*` tags (`REGISTRY_IMAGE=ghcr.io/roopsydaisy/fvs-containers`).
>   `ci.yaml` gates the other branches + PRs (it no longer runs on `main`).
> - **Stale `.vscode/mcp.json` assignment5 path** (flagged in roadmap item 8):
>   already removed.
> - **Known open gap (H1 in `docs/ASSESSMENT.md`):** the R workflows read
>   `data/*.csv` inventory inputs that are **not committed** (gitignored), so a
>   fresh clone can't run them until the fixture is added — see `data/README.md`.
> See `docs/ASSESSMENT.md` for the full review behind these corrections.

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
- **Pruned to lean R-only** (2026-05-29): removed the Python `src/fvs_tools/`
  (incl. `monte_carlo/`), its `tests/` + `pyproject.toml`/`uv.lock`, the analysis
  notebooks, and exploratory course docs/scripts + stale build leftovers. The
  chosen forester path is the R workflows; structured parameter sweeps / Monte
  Carlo will be a small future `scripts/r_workflow/generate_sweep.R` (`expand.grid`
  / sampling → `fvsMakeKeyFile(moreKeywords=)` → the `cluster/` batch → aggregate
  `FVSOut.db` via RSQLite). The pruned Python work remains recoverable in git
  history. (CI dropped its `python` job accordingly.)
- **Smoke test stamps the FVS engine version** (parses the `RV:` banner) and is
  cross-image (fvsOL guards self-skip where fvsOL is absent, e.g. the cluster
  image), so one gate works in both deliverable images.

- **Consolidated `docker/Dockerfile`** (replaces `Dockerfile.fvs` +
  `Dockerfile.webgui`): one common base `fvs-r-base` (FVS + R + renv pkgs + rFVS)
  with `webgui` (+ fvsOL/Shiny) and `cluster` (FVS + R + rFVS) targets. Hybrid FVS
  provenance via `--build-arg FVS_BASE=source` (default, compiles from
  `vendor/fvs`) or `ghcr` (bases off `usfs-fvs:FS2026.1`). **Validated on
  podman/Fedora** (`ENGINE=podman scripts/build_images.sh`): both images build
  from source and pass the in-image smoke test; both report the same engine
  (`RV:20260401`), and the cross-image gate self-skips the fvsOL guard in
  `fvs-engine`. Building this image surfaced + fixed three latent bugs the
  never-built original Dockerfiles carried (renv self-update EXDEV + missing
  `curl`; a dangling submodule `.git` breaking `git apply`; podman SELinux/UID
  bind-mount denial → smoke test baked into the image). **Both FVS_BASE paths
  verified on podman/Fedora**: `source` (compiles from `vendor/fvs`) and `ghcr`
  (extracts CLI + `.so` from `usfs-fvs:FS2026.1`; the `.so`s live in
  `/opt/fvs-bundle`, not beside the CLI) both pass the smoke test incl. the
  `rFVS/fvsLoad` embedder guard. `source` stays canonical (reproducible, no
  registry dependency, patchable); `ghcr` is the faster no-compile alternative.
- **CI** (`.github/workflows/ci.yaml`): a `python` job (uv sync + pytest) and an
  `images` job that runs `scripts/build_images.sh` — so "CI green" == "builds +
  works on the lab PC". The `images` path is now proven locally; the GitHub
  Actions run itself is unverified until first pushed.

## Key files

| Area | Files |
| --- | --- |
| Dev image / setup | `Dockerfile` (devcontainer; dev sibling of the common base), `.devcontainer/devcontainer.json`, `.devcontainer/postCreate.sh` |
| Deliverable images | `docker/Dockerfile` (one multi-target file: `fvs-r-base` → `webgui`, `cluster`) |
| Image build / CI | `scripts/build_images.sh` (portable docker/podman build + in-image smoke test), `.github/workflows/ci.yaml` |
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

## Submodule modifications — patches, not forks

We only modify **one** submodule: `vendor/fvs-interface` (3 small compatibility
patches in `patches/*.patch`, applied to its work tree by `apply_fvsol_patch.sh`).
`vendor/fvs` / `vendor/fvs-build` are unmodified — their only "dirt" is FVS build
artifacts + the NVEL nested submodule. So **we deliberately do NOT fork**: patch
files keep us on upstream commits, make the diff readable, and avoid fork-sync
maintenance (and the patches should ideally be upstreamed eventually). The pinned
commits never change from the patches, so `.gitmodules` sets `ignore = dirty` on
those two submodules — `git status` stays clean but still flags a real pointer
change. To update upstream: bump the submodule SHA, re-run the build, re-test the
3 patches.

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
  into the container at creation. Now present in-container
  (`RoopsyDaisy <rupertwilliamsnz@gmail.com>`), so plain `git commit` works — no
  `git -c user.name=… -c user.email=…` needed (earlier in this repo's history it was).
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
   `fvsMakeKeyFile(moreKeywords=...)` — to be packaged as a small
   `generate_sweep.R` (deferred; see below). microfvs's KCP library is a source of
   ready treatment keyword blocks.
2. **rFVS interactive (Path 2) — single-stand BUILT.** `scripts/r_workflow/project_stand.R`
   drives FVS as a library via `fvsLoad` + `fvsInteractRun`, harvesting per-cycle
   tree lists + summary into R in-memory (verified on CARB_2). A *parallel* rFVS
   batch (R+rFVS+`.so` image, per-task `fvsInteractRun` driver) is only needed if
   between-cycle R logic must run at HPC scale — the reference workflow doesn't,
   so it's deferred until a concrete need appears.
3. **Build validation — DONE on podman/Fedora** (`ENGINE=podman scripts/build_images.sh`):
   both images build and pass the in-image smoke test (incl. the `rFVS/fvsLoad`
   embedder guard; both report `RV:20260401`), on **both** `FVS_BASE=source` and
   `FVS_BASE=ghcr`. Remaining: the GitHub Actions run once pushed; and the
   Hellgate `.sif`/SLURM path (item 4).
4. **Hellgate validation (needs cluster access).** See the "[confirm on
   cluster]" list in `docs/HELLGATE_FVS.md`: partitions/limits, login-node
   network egress, fakeroot, modules, BeeGFS paths, real `.sif` under Apptainer.
5. **Prune for final product — DONE (2026-05-29).** Removed the Python tooling
   (`src/fvs_tools/` + `tests/` + `pyproject.toml`/`uv.lock`), analysis notebooks,
   exploratory course docs/scripts, and stale build leftovers (`lib/`), leaving a
   lean R-only repo. Recoverable in git history.
6. **CI is live & green:** pushed `fvs-container-build` to `github.com/RoopsyDaisy/fvs-containers`
   (renamed from `fors591`, see item 8); the GitHub Actions `images` job builds
   both images + runs the in-image smoke test on every push to
   `main`/`fvs-container-build` (passed in ~2:44).
7. **Remaining smaller items — mostly DONE.**
   - `scripts/r_workflow/generate_sweep.R` (R parameter-sweep / Monte Carlo
     helper) — **BUILT + verified end-to-end locally**: expands a
     `(stand × treatment)` grid (`expand.grid`, optional `SWEEP_SAMPLE` random
     subsampling), injects a `ThinBBA` residual-BA thinning via
     `fvsMakeKeyFile(moreKeywords=)`, unique base name per cell → own run dir +
     `FVSOut.db`, and writes `sweep_manifest.csv` (run_id → params). Tested:
     baseline + 60/120 ft² thinnings on CARB_2/CARB_3 → 0-failure batch; thinnings
     fire (BA drops to the residual in the thin year), and a residual target above
     standing BA correctly no-ops. To sweep a different treatment, edit
     `treat_record()`. (`scripts/r_workflow/README.md` documents the track + the
     RSQLite aggregation join + the FVS pre/post-thin double-summary-row gotcha.)
   - Docs pass (per-use-path quickstarts) — sweep quickstart + aggregation added.
   - **CI `paths:` filter — DONE.** `ci.yaml` now has `paths-ignore`
     (`**.md`, `docs/**`, `LICENSE`) on both `push` and `pull_request`, so
     docs-only pushes skip the ~3-min image rebuild. (This unblocks pushing the
     stranded doc commits without triggering a build.)
8. **Repo renamed `fors591` → `fvs-containers`; GHCR publish READY (auto-publish
   not yet enabled).** The GitHub repo was renamed in place (history + submodules
   carried over via the redirect; the old URL still resolves). In-tree refs
   updated: `.devcontainer/devcontainer.json` `"name"` → `fvs-containers`, and a
   ready publish workflow at `.github/workflows/publish.yaml` (`packages: write` +
   `docker/login-action`, builds via `scripts/build_images.sh`, tags + pushes
   `…-webgui` / `…-engine`) with `REGISTRY_IMAGE=ghcr.io/roopsydaisy/fvs-containers`
   (GHCR requires lowercase). The workflow is **ready but intentionally inert**:
   only `workflow_dispatch` is active (the auto `push` trigger is commented out),
   so nothing publishes on a push yet.

   **To finish the GHCR rollout** (the one remaining step): uncomment the `push:`
   trigger in `publish.yaml` (or use the Actions tab "Run workflow" for a one-off).
   Then images are pullable
   (`apptainer pull docker://ghcr.io/roopsydaisy/fvs-containers-engine:ie` — the
   clean Hellgate path).

   **Deliberately left alone / still open:**
   - **`fors591-claude` Docker volume — kept as-is on purpose.** It holds Claude's
     persistent memory + chat history (mounted at `~/.claude`). Renaming it would
     orphan that data, so the name stays (it's cosmetic; an inline note in
     `devcontainer.json` records why). A host-side backup lives in
     `.claude-backup/` (gitignored). `git pull` and devcontainer rebuilds are
     safe — they don't touch named volumes. The only trap: renaming the **local
     clone folder** changes the workspace path and thus the memory's project key
     (`projects/-workspaces-fors591/`) — keep the local folder name, or migrate
     that subdir if you rename it.
   - `Dockerfile:58` `WORKDIR /workspaces/fors591` — left unchanged: it pairs with
     the *local folder* name (the mount path), which the GitHub rename doesn't
     change. Update it only if/when the local clone folder is renamed too.
   - **Unrelated cleanup spotted during the inventory:** `.vscode/mcp.json:43`
     points an MCP server at `outputs/assignment5/harv1/FVSOut.db` — a path under
     the **pruned** assignment5 work that no longer exists. Stale regardless of the
     rename; remove or repoint that MCP entry.

## How to resume in a fresh session

**Current state:** lean R-only repo; both deliverable images build + pass the
in-image smoke test on `FVS_BASE=source` and `ghcr`; CI is green on GitHub. The
smaller roadmap items are now done: the R sweep helper
(`generate_sweep.R`, verified end-to-end), the docs pass, and a CI `paths-ignore`
filter (so docs-only pushes skip the image rebuild). The GHCR publish workflow is
drafted but inert (`.github/workflows/publish.yaml`) pending the rename. The main
remaining piece is the **repo rename** (checklist in roadmap item 8 above), then
flip `publish.yaml` on. Branch `fvs-container-build` was ahead of `origin` by the
docs commits plus this pass's work — now that the `paths-ignore` filter is in,
pushing the docs/sweep changes no longer triggers a needless image rebuild.

1. Read this file first, then `docs/HELLGATE_FVS.md`, `cluster/README.md`,
   `scripts/r_workflow/README.md`, and `README.md`. `git log --oneline` on
   `main` for the change history (the old `fvs-container-build` dev branch is gone).
2. Local sanity checks (devcontainer):
   - `Rscript scripts/smoke_test.R` → 5 guards incl. `rFVS/fvsLoad` + `RV:` stamp.
   - R batch track: `Rscript scripts/r_workflow/build_input_db.R outputs/r_batch/FVS_Data.db CARB_2,CARB_3,CARB_4`
     then `Rscript scripts/r_workflow/generate_keyfiles.R outputs/r_batch CARB_2,CARB_3,CARB_4 55`
     then `FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT="$PWD/outputs/r_batch/FVS_Data.db" cluster/run_local.sh outputs/r_batch/keyfiles.txt outputs/r_runs`.
   - WebGUI: `bash scripts/run_webgui.sh` (port 3838).
   - Image builds need a container runtime (NOT in the devcontainer) — run
     `ENGINE=podman bash scripts/build_images.sh` on the lab PC, or let CI do it.
   - R sweep track: `Rscript scripts/r_workflow/build_input_db.R outputs/r_sweep/FVS_Data.db CARB_2,CARB_3`
     then `SWEEP_RESID_BA="none,60,120" Rscript scripts/r_workflow/generate_sweep.R outputs/r_sweep CARB_2,CARB_3 55`
     then `FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT="$PWD/outputs/r_sweep/FVS_Data.db" cluster/run_local.sh outputs/r_sweep/keyfiles.txt outputs/r_sweep_runs`.
3. **Next actions (all in the roadmap above; none blocking):**
   - **The rename, then GHCR publish:** rename the repo off the course name
     `fors591` (checklist in roadmap item 8), then set `REGISTRY_IMAGE` +
     uncomment the `push:` trigger in `.github/workflows/publish.yaml` so images
     are `apptainer pull`-able for Hellgate. Sequence the rename *before* enabling
     publish so the GHCR namespace is set once.
   - **Parked on access:** Hellgate validation — see the "[confirm on cluster]"
     list in `docs/HELLGATE_FVS.md`; the lecturer has a (possibly-stale) Hellgate
     ID and is prepping `stand.key` examples for a lab visit to run the batch.
