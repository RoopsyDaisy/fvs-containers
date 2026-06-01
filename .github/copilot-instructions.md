# Repo-specific guidance for AI assistants

## Big picture
- This is a **reproducible packaging layer** around the USDA Forest Vegetation
  Simulator (FVS) and the FVSOnline WebGUI (fvsOL). It is **R + shell + Docker**,
  not Python. (An earlier Python/uv tool tree was pruned; ignore any lingering
  references to `src/`, `pyproject.toml`, `uv`, or notebooks.)
- One multi-target image (`docker/Dockerfile`): a common `fvs-r-base` (FVS engine
  + R + renv-pinned packages + rFVS) with `webgui` (+ fvsOL/Shiny) and `cluster`
  (HPC engine) targets.
- FVS itself comes from pinned submodules under `vendor/` and is compiled by the
  **Meson `fvs-build` overlay** via `scripts/build_fvs.sh`; the R package set is
  pinned with `renv` against a dated P3M snapshot.

## Environment & workflows
- **R env:** `renv::restore(prompt = FALSE)` (packages come from `renv.lock` /
  P3M binaries, not apt — r2u's `bspm` hook is disabled in the image).
- **Build FVS locally:** `scripts/build_fvs.sh vendor/fvs ie /tmp/fvs-ie`.
- **Build images (needs a container runtime, NOT the devcontainer):**
  `ENGINE=podman scripts/build_images.sh` (docker in CI).
- **Regression gate:** `Rscript scripts/smoke_test.R` (R env + FVS engine +
  rFVS `.so` load; self-skips the fvsOL guards in the cluster image).
- **WebGUI:** `bash scripts/run_webgui.sh` (port 3838).
- **R workflows + HPC batch moved out:** the R keyword generators and the SLURM +
  Apptainer batch runner now live in the companion repo
  [fvs-hpc-toolkit](https://github.com/RoopsyDaisy/fvs-hpc-toolkit), which runs
  against the engine image this repo publishes. This repo builds + publishes the
  image and validates the **engine** (`tests/run_tests.R`, integration only).

## Coding patterns & conventions
- Shell: `set -euo pipefail`, resolve paths with `readlink -f`, fail loudly with
  actionable messages (see `scripts/*.sh`).
- R: base-R style, env-var-configurable, **reuse FVS's own helpers**
  (`rFVS::fvsMakeKeyFile`, `fvsInteractRun`) rather than reinventing them.
- Run FVS via `FVS<variant> --keywordfile=<name>` (works for both database-style
  and flat-file keyword files); do **not** pipe the name on stdin.
- FVS exit codes 0/10/20 are all success; per-stand problems land in the
  `FVS_Error` table, not the exit code.

## External dependencies & data handling
- `vendor/*` are SHA-pinned submodules; modify `vendor/fvs-interface` only via
  `patches/*.patch` (applied by `scripts/apply_fvsol_patch.sh`) — patches, not
  forks. `vendor/fvs` and `vendor/fvs-build` stay unmodified.
- Inventory CSVs and generated databases are gitignored; document data sources in
  `data/README.md`, never commit large data or chat history.

## Productivity tips
- Use the devcontainer for a consistent environment; image builds run on a host
  with a container runtime or in CI, not inside the devcontainer.
- Keep doc prose in sync with the scripts — this repo's docs have drifted before
  (see `docs/ASSESSMENT.md`).
