# Upstream/reference review — practices worth adopting

**Date:** 2026-05-29
**Scope:** what the repos we depend on or reference do for **container delivery,
testing/CI, and build system** that this repo (`fvs-containers`) might adopt.
**Output:** findings + recommendations only — no code changes in this pass.
**Method:** read-only review of:
- `vendor/fvs-build` — the Meson overlay we vendor (SHA `63d1132`)
- `microfvs` — Vibrant Planet's REST+KCP FVS service (the non-vendored
  *reference* repo; cloned at HEAD `f074dc2` for this review)
- our own `docker/Dockerfile`, `.github/workflows/*`, `.devcontainer/`

> The USDA submodules (`vendor/fvs`, `vendor/fvs-interface`) are upstream FVS
> engine/interface source; their build/CI is FVS's own and out of scope here
> beyond what `fvs-build` already wraps.

---

## 0. What we already do (so this isn't re-recommended)

| Practice | Status here |
|---|---|
| Multi-stage Dockerfile, one base → multiple targets | ✅ `fvs-r-base` → `webgui`/`cluster` |
| FVS-as-container option (consume `usfs-fvs`) | ✅ `FVS_BASE=ghcr`, `ARG FVS_TAG=FS2026.1` |
| Build-from-source option | ✅ `FVS_BASE=source` via `fvs-build` overlay |
| Single build script shared by CI + workstation | ✅ `scripts/build_images.sh` |
| In-image smoke test + **real engine integration test** | ✅ `smoke_test.R`, `tests/` (this PR) |
| GHCR publish gated on build+test | ✅ `publish.yaml` |
| Build-once-test-twice (CI on branches, publish on main) | ✅ |
| renv exact pinning for R deps | ✅ `renv.lock` |
| Devcontainer with `postCreateCommand` | ✅ `.devcontainer/postCreate.sh` |

The gaps below are things **both** reference repos do that we don't.

---

## 1. High-value adoptions (recommend)

### A1 — A lint/static-analysis gate (`pre-commit` + a `lint` CI job)
**Both** repos run this; we have **none** (no `.pre-commit-config.yaml`, no lint
workflow). This is the biggest single gap.

- microfvs (`.pre-commit-config.yaml`): `gitleaks` (secret scan), `ruff`
  (lint+format), `mypy`. CI `lint.yaml` runs `uv sync --frozen` then the
  pre-commit action — **separate, native, fast**, distinct from the heavy
  Docker test job.
- fvs-build (`.pre-commit-config.yaml` + `lint.yml`): `actionlint` (type-checks
  `${{ }}` expressions in our workflows!), `yamllint`, **`hadolint`** (Dockerfile
  linter, pinned), `ruff`. pre-commit envs cached on the config hash.

**For us (R + shell + Docker, no Python):** the directly-applicable hooks are
**`actionlint`** (we have 2 workflows and just hit a dead-branch trigger bug it
would catch), **`hadolint`** (we have 2 Dockerfiles), **`shellcheck`** (we have
many `set -euo pipefail` scripts — high value), **`gitleaks`**, and for R
**`lintr`/`styler`** via a local hook. A lean `lint.yaml` running
`pre-commit run --all-files` natively is cheap and gates every PR.
*Effort: low. Risk: low. Payoff: high (catches the class of bug we already hit).*

### A2 — Programmatic FVS-output assertions, multi-variant (already half-done)
microfvs is the model for what we just started:
- `test_fvs_build.py` — **parametrized over every FVS variant**
  (`@pytest.mark.parametrize("variant", FvsVariant)`), writes a per-variant
  keyfile, runs the binary, asserts `returncode==0`, output exists, and
  **`"WARNING:"`/`"ERROR:"` not in the `.out`**.
- `test_run_fvs.py` — full run, asserts the **SQLite output tables are populated**
  (parsed to DataFrames), not just that files exist.
- Reference inventory lives in code (`constants.py: TEST_STANDINIT/TREEINIT`,
  real stand `061608985105`); keyfiles versioned at `tests/keyfiles/{VARIANT}.key`.

**For us:** our new `tests/integration/test_fvs_iet01.R` already does the
strongest part (parses `.sum`, asserts a real multi-cycle projection). Worth
borrowing: (1) the **no-`WARNING:`/`ERROR:` in `.out`** assertion (cheap, we
have the text already); (2) a **per-variant** fixture table so the test isn't
`ie`-only — even just adding one more variant proves the build matrix. Note our
`iet01` keyfile uses flat-file `.tre` input (good — exercises the
`--keywordfile=` path our cluster batch needs), whereas microfvs uses DB input;
keeping both styles covered is a plus.
*Effort: low–med. Risk: low.*

### A3 — OCI provenance labels on published images
fvs-build is exemplary here; **we currently emit none** (no `LABEL` in our
Dockerfile). It stamps both standard `org.opencontainers.image.*` and custom
`org.vibrantplanet.fvs.{source-sha,source-ref,gfortran-version,...}` labels,
populated from build ARGs, so `docker inspect | jq .Config.Labels` tells you
exactly which FVS source + toolchain produced an image.

**For us:** add `LABEL`s to the `webgui`/`cluster` targets carrying at minimum
the FVS variant, `FVS_BASE` (source vs ghcr), the `vendor/fvs` SHA (or
`usfs-fvs` tag), and the git SHA of this repo. We publish moving `:ie`/`:latest`
tags that get overwritten — labels are how you later tell two `:latest` pulls
apart. Pairs naturally with our existing `ARG FVS_TAG/FVS_BASE/FVS_VARIANT`.
*Effort: low. Risk: none. Payoff: high for a repo whose whole point is
reproducible provenance.*

### A4 — GitHub Actions buildx layer cache
**Both** repos cache Docker layers across runs; we don't (our `ci.yaml` comment
even flags "add a buildx layer cache if build time becomes a problem"). microfvs
uses `cache-from/to: type=gha`. Our from-source build (FVS compile + renv
restore) is the slowest in this whole set — this is the highest *time* payoff.
*Effort: low (switch to `docker/build-push-action` or `buildx` with
`--cache-to type=gha`). Risk: low. Caveat: from-source release builds may
**want** cache misses for reproducibility — cache PR/branch builds, not the
`publish.yaml` main build (fvs-build makes exactly this distinction via a cache
key that includes `source_ref`).*

---

## 2. Medium-value (consider)

### M1 — `workflow_call` reusable workflows
fvs-build factors everything into reusable workflows
(`build-native-linux.yml`, `build-container-linux.yml`) + composite actions, with
thin `dispatch-*.yml` drivers defaulting to `push: false`. If we ever add a
second variant, a Windows path, or a downstream repo that wants our images,
refactoring `build_images.sh`'s callers into a `workflow_call` workflow pays off.
Today, with one script and two workflows, it's **premature** — note it, don't do
it yet.

### M2 — Native binary independence check
fvs-build's smoke test asserts the **standalone `FVS<variant>` exe does NOT link
`FVS<variant>.so`** (`ldd | grep` guard) — catches an embedder/CLI mixup. Our
`smoke_test.R` checks the `.so` *loads* (for rFVS) but not that the CLI is
independent of it. Cheap addition to our smoke test.

### M3 — `.dockerignore`
Neither agent found one for us, and we confirmed we have none. Our build context
is the whole repo (incl. `vendor/` submodules, `docs/`, `tests/`). A
`.dockerignore` shrinks context-upload time and avoids cache-busting the build
on doc-only changes. *Low effort; modest payoff.*

### M4 — Devcontainer `postCreate` installs the hooks
microfvs's `postCreateCommand` ends with `pre-commit install`, so a fresh
devcontainer is immediately gated. If we adopt A1, have our `postCreate.sh`
install the hooks too, so local commits get the same checks as CI.

---

## 3. Deliberately NOT adopting (with reasons)

- **uv / Python toolchain** — microfvs is Python; we're R+shell. `renv.lock`
  already gives us the same exact-pinning discipline microfvs gets from
  `uv.lock --frozen`. No action.
- **`mypy` / typed-model layer** — microfvs's Pydantic `FvsResult` models are
  for its REST API; we have no API surface. N/A (an R `lintr` hook is the
  proportionate analogue — see A1).
- **nbval notebook CI** — microfvs validates changed `.ipynb`. We have no
  notebooks. Skip unless we add R Markdown examples.
- **No-in-container-test stance** — fvs-build deliberately *doesn't* smoke-test
  its container (relies on native test + provenance). We do the opposite (test
  in-image) and should **keep** ours: our images carry an R stack whose runtime
  wiring is exactly what's broken before, so in-image testing earns its keep.
- **SPDX SBOM via syft** (fvs-build) — nice supply-chain hygiene, but heavier
  than our scale warrants today. Revisit if images are distributed beyond the
  course/cluster.

---

## 4. Suggested order if we act

1. **A1** lint gate (`pre-commit` + `lint.yaml`: actionlint, hadolint,
   shellcheck, gitleaks, lintr) — catches the bug class we already hit.
2. **A3** OCI provenance labels — trivial, directly on-mission.
3. **A4** buildx GHA cache for PR/branch CI — biggest time saver.
4. **A2** extend the integration test: no-`ERROR:` assertion + a second variant.
5. Then the M-items as convenient (M2/M3 are quick).

All of the above are independent, each a small PR through the
`docs/WORKFLOW.md` flow. None blocks merging the current PR #1.

---

## Appendix — key source references

**fvs-build:** `docker/Dockerfile.runtime` (matched `ubuntu-24.04` base, flat
bundle→PATH copy, OCI+custom `LABEL`s L83-103), `meson.build` (per-variant
obj/shlib/exe, `name_prefix=''` for `FVS<v>.so`), `.github/workflows/
build-native-linux.yml` (meson cache key incl. `source_ref` L187; native smoke
test + `ldd` independence guard L210-231), `tools/ci/provenance.py`
(`compile_commands.json` → resolved flags), `.pre-commit-config.yaml` +
`lint.yml`.

**microfvs:** `Dockerfile` (`ARG FVS_IMAGE=ghcr.io/...usfs-fvs:${FVS_TAG}`,
multi-stage dev/runtime, `uv` from `ghcr.io/astral-sh/uv:0.7`), `.github/
workflows/pytest.yaml` (Docker test + `cache-from/to: type=gha`) + `lint.yaml`
(native, pre-commit), `.pre-commit-config.yaml` (gitleaks/ruff/mypy),
`microfvs/tests/test_fvs_build.py` (parametrized-per-variant engine test,
no-`WARNING:`/`ERROR:` assertion), `microfvs/utils/tests/test_run_fvs.py`
(asserts populated SQLite output tables), `microfvs/constants.py` (in-code
reference inventory), `.devcontainer/devcontainer.json` (`postCreate`:
`uv sync --frozen && pre-commit install`).
