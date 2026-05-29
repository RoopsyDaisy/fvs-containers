# Repository assessment — fvs-containers

**Date:** 2026-05-29
**Scope:** goals vs. implementation, fit for purpose, overlap with existing
tools, and a senior-developer + stakeholder review.
**Method:** read-only review of the full tree (docs, Dockerfiles,
build/cluster/R-workflow scripts, CI/publish workflows, config, submodule
state). No live image build or FVS run was possible in the review environment
(no container runtime; submodules unpopulated), so "verified locally" claims in
`PROJECT_STATUS.md` were taken at face value and assessed for *reproducibility
by a third party*, not re-run.

> This document records the assessment. The companion commits on
> `claude/repo-assessment-review-ft5yJ` act on the must-fix and should-fix
> items below; each is cross-referenced by its ID (H1, H2, …).

---

## 1. What this repo is (goals)

A reproducible packaging layer around the **USDA Forest Vegetation Simulator
(FVS)** and its **FVSOnline WebGUI (fvsOL)**, originally for a University of
Montana forestry course (FORS591) plus a lecturer's HPC batch need. Three
delivery shapes off one shared engine base:

| Deliverable | Audience | Mechanism |
|---|---|---|
| **WebGUI image** | foresters/students | fvsOL Shiny app, port 3838 |
| **Engine/cluster image** | scripted runs | FVS CLI + R + rFVS |
| **Apptainer + SLURM batch** | researchers on Hellgate | `.sif` + array job |

Stated value-add over the prebuilt `usfs-fvs` image: a containerized GUI, an HPC
batch runner, R keyword-generation / interactive workflows, and a pinned,
reproducible R + engine build.

## 2. Verdict

The engineering is genuinely good; the repository was **not in a
fit-for-purpose state for a fresh clone**, and the prose had **drifted badly
from the code**. Two blocking defects and a broad doc-drift problem dominated.
The accompanying commits address the doc drift, the license gap, and the data
discoverability problem; the data *fixture* itself remains a maintainer step
(see H1).

---

## 3. Blocking / high-severity findings

### H1 — The R workflow can't run for anyone: input data is missing *and* gitignored
All four R scripts (`build_input_db.R`, `generate_keyfiles.R`,
`generate_sweep.R`, `project_stand.R`) hard-code:

```
data/FVS_Lubrecht_2023_FVS_StandInit.csv
data/FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv   # note the doubled "FVS_FVS"
```

But there is **no `data/` directory**, `.gitignore` ignored `data/` and
`*.csv`, and **no CSV was tracked**. Every documented quickstart in `README.md`
and `scripts/r_workflow/README.md` therefore fails at step 1 on a clean
checkout. The PROJECT_STATUS claim "verified end-to-end (296 stands → … →
0-failure batch)" holds only on the author's disk. There was no fixture, no
sample, and no documented data source.

**Action taken:** added `data/README.md` documenting the required files, the
FVS-standard schema, the UTF-8-BOM CSV format, and where to obtain the Lubrecht
inventory; un-ignored `data/README.md`; and added a shared preflight
(`scripts/r_workflow/data_paths.R`) so a missing file now errors with a clear
pointer instead of a raw `read.csv` crash. **Still a maintainer step:**
committing the real (or a validated synthetic) fixture — deliberately not
fabricated here because it cannot be validated against the FVS engine in this
environment, and a malformed fixture is worse than none.

### H2 — `.github/copilot-instructions.md` described a project that no longer exists
It documented a **Python/uv** project (`pyproject.toml`, `src/<package>/`,
`tests/`, `notebooks/`, `pytest`, `ruff`, `black`) — all pruned. The file is
read specifically by AI assistants, so it actively misled them.
**Action taken:** rewritten for the R-only repo.

---

## 4. Documentation drift (medium, pervasive)

The code moved on; several docs didn't.

- **`docs/HELLGATE_FVS.md` taught the opposite of the code.** It stated FVS
  "reads the keyword filename from standard input, **not** from a
  `--keywordfile` flag" and showed `echo stand.key | … FVSie`. But
  `cluster/fvs_run_one.sh`, `cluster/README.md`, and PROJECT_STATUS all
  deliberately use `--keywordfile=` *because* stdin breaks on flat-file keyword
  files. **Fixed.**
- **`docs/BUILD.md` documented a replaced build.** It described the hand-rolled
  **CMake** process ("GAP #1 `wdbkwtdata.inc`", "GAP #2 `FVSie.so` symlink") as
  what `build_fvs.sh` does — but the script now uses the **Meson `fvs-build`
  overlay**, which handles those upstream. `README.md` repeated the stale "two
  undocumented Linux gotchas it handles" framing. **Fixed** (CMake gaps demoted
  to a historical note).
- **`docs/PROJECT_STATUS.md` lagged the git log.** It named branch
  `fvs-container-build` (gone), called `publish.yaml` "intentionally inert"
  (the push trigger is now live per commit `89a3896`), and listed the rename as
  pending (done per `d48c5b0`). Its own flagged TODO (stale `.vscode/mcp.json`
  assignment5 path) was already resolved. **Fixed** (current-state header +
  corrected the stale specifics).
- **The devcontainer `Dockerfile` header** referenced consolidated-away files
  (`docker/Dockerfile.fvs` / `.webgui`) and still installed **Python3 + uv**
  for the pruned tooling. **Fixed** (header corrected, Python/uv removed). The
  `WORKDIR /workspaces/fors591` line is **intentionally left** — it pairs with
  the local clone folder name and the Claude state volume key (see
  PROJECT_STATUS item 8).
- **`postCreate.sh`** still printed the rejected stdin invocation. **Fixed.**

## 5. Lower-severity / hygiene

- **No `LICENSE`** despite publishing images to GHCR. **Action taken:** added
  **MIT** (owner's choice) — appropriate for a thin wrapper over USDA
  public-domain FVS/rFVS/fvsOL plus the repo's own scripts.
- **CI trigger orphaned.** `ci.yaml` pushed-branch filter named the deleted
  `fvs-container-build`, so only PRs (and `main` via `publish.yaml`) got CI.
  **Action taken:** switched to `branches-ignore: [main]` so any feature branch
  is gated again, with `main` left to `publish.yaml`.
- **Dev tooling in the deliverable surface** (`.github/agents/*.agent.md`,
  `mcp.json`, `default.code-workspace`) — harmless noise; left as-is.
- **Submodules** are correctly SHA-pinned with a patches-not-forks strategy —
  the strongest part of the reproducibility story.

## 6. Does it duplicate existing work?

Partly, and the README is honest about it:

- **The engine build** now overlaps heavily with Vibrant Planet's **`fvs-build`**
  (Meson overlay) and **`usfs-fvs`** GHCR images — so much that this repo
  *consumes* them (`FVS_BASE=ghcr`). The "compile from source" value-prop has
  eroded; the source path is still defensible (no registry dependency,
  patchable, pinned) but is now a thin wrapper, not original engine work.
- **`microfvs`** (REST + KCP) exists for on-demand single-stand calls;
  HELLGATE_FVS correctly argues it's the wrong tool for N-independent batch.
- **Genuinely additive / not duplicated:** the containerized fvsOL WebGUI with a
  fully pinned `renv` closure + compatibility patches, and the SLURM-array batch
  harness. These are the parts worth keeping, and the framing should center on
  them rather than on "we build FVS from source."

## 7. Code quality (senior-dev view)

Where it counts, the implementation is clean and professional: shell scripts use
`set -euo pipefail`, `readlink -f`, loud preflight checks, and a single shared
`fvs_run_one.sh` across SLURM and local paths (good DRY). FVS exit-code handling
(STOP 0/10/20 = success; per-stand errors in `FVS_Error`) reflects real domain
knowledge. `smoke_test.R` is a thoughtful gate that pins the exact
dependency-drift bugs and actually `dyn.load`s the `.so`. R scripts reuse FVS's
own generators (`fvsMakeKeyFile`, `fvsInteractRun`) rather than reinventing them.
The comments capture hard-won "why" — a strength, *as long as they stay true*,
which several no longer were (§4).

## 8. Stakeholder view

- **The lecturer's actual deliverable — the Hellgate HPC batch — has never run
  on Hellgate.** Everything is validated locally / on podman; the real
  `.sif`-under-Apptainer, SLURM submission, partitions, fakeroot, and BeeGFS
  paths are all `[confirm on cluster]`. Openly documented, but it remains the
  single largest delivery risk: the thing the customer said they'd use is
  unproven on the target.
- A student on the **WebGUI** path is fine (fvsOL ships its own training data);
  a colleague trying the **R workflows** was blocked by H1.

## 9. Prioritized recommendations

**Must-fix (unblocks usability/reproducibility)**
1. **H1** — ship a sample/real inventory fixture under `data/`, or document the
   source (partially done: contract documented + guarded; fixture pending).
2. **H2** — rewrite/delete `copilot-instructions.md` (done).
3. Add `LICENSE` (done — MIT).

**Should-fix (restore doc trust)**
4. `docs/HELLGATE_FVS.md` → `--keywordfile=` (done).
5. `docs/BUILD.md` + `README.md` → Meson/`fvs-build` (done).
6. `docs/PROJECT_STATUS.md` → current state (done).
7. devcontainer `Dockerfile` header + drop Python/uv; `postCreate.sh` hint (done).
8. `ci.yaml` push trigger → a branch that exists (done).

**Nice-to-have (not done — owner's call)**
9. Move dev-only tooling out of the shipped surface, or document it.
10. Reframe the README value-prop around the WebGUI + batch + R layer.
11. Validate on Hellgate; only then can the headline deliverable be called done.

---

## Addendum (2026-05-29) — test layer + workflow

A follow-up added a base-R test suite (`tests/`, run by `tests/run_tests.R`,
baked into the images and run by `build_images.sh` so it gates **both** CI and
the GHCR publish), plus a lightweight branch/PR/test-gate workflow
(`docs/WORKFLOW.md`, `.github/pull_request_template.md`). Two notes:

- **`publish.yaml` already builds + smoke-tests before pushing**, so the earlier
  "auto-publish on main is the big risk" framing was overstated: a broken build
  can't publish. The real lever was that the *gating* test was thin — hence the
  new suite. Branch protection on `main` (documented in `WORKFLOW.md`) is now
  defense-in-depth, and is a manual GitHub setting (not script-encoded).
- **Bug surfaced by the new keyword-writer test:**
  `fvs_keyword_file_functions.R` formatted `TOPOCODE` but the tree-file `sprintf`
  emitted `tl$TOPO` — a non-existent column on `TOPOCODE`-schema input, which
  (via zero-length `sprintf` recycling) silently produced an **empty `.tre`
  file** (FVS would then run on zero trees). Fixed to `tl$TOPOCODE` and locked
  with `tests/unit/test_keyword_writer.R`.

> Caveat: R could not be executed in the review/build environment, so the new
> tests and the writer fix were **validated by CI in-image, not run locally**.
</content>
</invoke>
