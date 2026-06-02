# fvs-containers patches

Three small source patches against the vendored `vendor/fvs-interface` submodule
(USDA `ForestVegetationSimulator-Interface`, pinned at `57b9aa3`), applied to the
work tree at build time by `scripts/apply_fvsol_patch.sh` (Docker build stages
and `.devcontainer/postCreate.sh`). They are **patches, not a fork** (see
`docs/PROJECT_STATUS.md` → "Submodule modifications").

The `.patch` files are plain diffs with no embedded rationale — **this file is
the rationale of record.**

Pinned environment (Posit Package Manager snapshot **2026-05-27**, `renv.lock`):

| | version |
|---|---|
| R | 4.6.0 |
| RSQLite | 3.53.1 (bundled SQLite 3.53.1) |
| DBI | 1.3.0 |
| roxygen2 | 8.0.0 |

> **Ground-truth note (2026-06-02).** These patches were originally filed
> upstream on assertion, then re-investigated against the pinned env (live
> reproduction on a box with R 4.6.0 + the pinned RSQLite). Verdicts below.

## Summary

| Patch | Fixes | Reproduces on pinned env? | Upstream |
|---|---|---|---|
| `fvsOL-rsqlite-temp-tables.patch` | RSQLite ≥3 rejects any `DBI::SQL()` name in `dbWriteTable` | ✅ verbatim: `Named parameters not used in query: name` | PR open (reframe); now covers **all 12** sites (11 `temp.X` literals + the XLSX-export dynamic name) |
| `rFVS-encoding.patch` | roxygen2 8 doc-regen warning | ✅ `✖ roxygen2 requires "Encoding: UTF-8" / Current encoding is NA` | PR open (reframe) |
| `fvsOL-staged-install.patch` | (historical) staged-install path-record error | ❌ did **not** reproduce on R 4.6.0 | local-only; **not** upstreamed |

## `fvsOL-rsqlite-temp-tables.patch`

**What:** converts every `dbWriteTable(con, DBI::SQL(<name>), df)` →
`dbWriteTable(con, "<name>", df, temporary=TRUE, overwrite=TRUE)` at **all 12**
sites in fvsOL that pass a `DBI::SQL()` object as the table name:

- `server.R` (6): `temp.Grps` ×2, `temp.SGrps`, `temp.SEGrps`, `temp.mapsCases`, `temp.uidsToGet`
- `writeKeyFile.R` (1): `temp.RunStds` — **keyword-file generation path**
- `externalCallable.R` (2): `temp.Stds`, `temp.getStds`
- `fvsRunUtilities.R` (2): `temp.Stds` ×2
- `server.R` (1, the **XLSX-export** path, `output$dlFVSOutxlsx`): `DBI::SQL(casesToGet)`
  — a *dynamic*, attached-schema name (see "XLSX-export site" below)

Each `temp.*` write keeps its downstream `temp.X` query references intact (the
`temporary=TRUE` form lands the table in the temp schema, still queryable as
`temp.X`).

**Why (reproduced live on the pinned env):**

```r
library(DBI); library(RSQLite)
con <- dbConnect(SQLite(), ":memory:")
dbWriteTable(con, DBI::SQL("temp.Grps"), data.frame(Stand_ID="", Grp=""))
#> Error: Named parameters not used in query: name
dbWriteTable(con, "Grps", data.frame(Stand_ID="", Grp=""), temporary=TRUE, overwrite=TRUE)  # works
```

A genuine runtime bug (bare `:memory:`, stock packages), not container-specific.

**Scope history (why all 11, not 6):** the original patch fixed only the 6
`server.R` sites (the GUI stand-selection path exercised by `smoke_test.R`
guard 2). The other 5 were **live breakages in the container** —
`writeKeyFile.R:436` throws on any real keyword-generation / simulation run —
masked only because no full GUI run had been done and guard 2 exercises the
pattern in isolation, never these actual call sites (false green).

**XLSX-export site (the 12th, added 2026-06-02 — review finding):** the
"Output .xlsx for current run" download handler (`server.R`, `output$dlFVSOutxlsx`,
button at `fvsOL/R/ui.R`) builds a `CaseID` filter table with
`dbWriteTable(…, name=DBI::SQL(casesToGet), …)`. Same error class (a `DBI::SQL()`
name) → same `Named parameters not used in query` crash the moment a user exports
to Excel; it also carried a pre-existing `overwirte=` typo (so overwrite never
applied). It was a *dynamic* name (`casesToGet = "tmp….casesToGet"`, an
attached-`:memory:`-db alias), so it didn't match the `"temp.` literal scan and was
initially scoped out. The attached db was used **only** for that one table (attached
then detached a few lines later), so the fix drops the attach/detach and writes a
plain **temporary table** instead — the same `temporary=TRUE` pattern as the other
11 (already proven on the pinned env by `smoke_test.R` guard 2), so no new
pinned-env risk; the `overwirte` typo is fixed in passing. Unit-level fix is solid;
the remaining confirmation is a GUI click-through (build the webgui image, run a
projection, click the button — no "Named parameters…" error, a non-empty `.xlsx`).

All 12 are now converted, and the completeness guard in `apply_fvsol_patch.sh`
fails the build if **any** `DBI::SQL()`-as-name `dbWriteTable` remains (broadened
from the old `"temp.`-literal-only scan, so it now also catches a regression of
the dynamic XLSX form).

**Intentionally NOT converted (different case — flag before touching):**

- `server.R:7712` `dbWriteTable(…, "temp.FVS_ClimAttrs", …)` — plain string
  (creates a dot-named table in `main`, not the temp schema); a separate latent
  issue, not this error class (so the guard, which matches only `DBI::SQL()`
  names, doesn't flag it).

**Upstream:** PR open from `RoopsyDaisy:upstream-pr/fvsol-rsqlite-temp-tables`
(USDA repo). Reframe the body around the real error + pinned versions.

## `rFVS-encoding.patch`

**What:** adds `Encoding: UTF-8` to `rFVS/DESCRIPTION` (the sibling
`fvsOL/DESCRIPTION` already declares it).

**Why (reproduced live):** `rFVS` ships no committed `NAMESPACE`/`man/`, so the
build regenerates docs with `roxygen2::roxygenize()` (`docker/Dockerfile`,
`postCreate.sh`). Under roxygen2 8.0.0, with no `Encoding` field, that step
warns:

```
✖ roxygen2 requires "Encoding: UTF-8"
ℹ Current encoding is NA
```

Adding the field silences it. This is **not** the R CMD check non-ASCII NOTE
(rFVS sources are pure ASCII — that NOTE never fires); it is purely the roxygen2
doc-regeneration warning. Upstream relevance: rFVS is roxygen-managed, so anyone
regenerating its docs on roxygen2 ≥7.x hits this.

**Upstream:** PR open from `RoopsyDaisy:upstream-pr/rfvs-encoding`. Reframe the
body to quote the roxygen2 message and drop the "R CMD check warning" framing.

## `fvsOL-staged-install.patch`

**What:** adds `StagedInstall: no` to `fvsOL/DESCRIPTION`.

**History:** the 2026-05-28 from-scratch build hit
`ERROR: hard-coded installation path … use --no-staged-install` during
`renv::install` of fvsOL.

**Did NOT reproduce (pinned env, R 4.6.0):** the faithful path —
`roxygen2::roxygenize()` then staged `R CMD INSTALL fvsOL` — exits 0 and passes
R's "record of temporary installation path" check; no `00LOCK` error. The
hypothesized bake site (top-level `source(system.file(...))` in `server.R`,
evaluated during the lazy-load build) does **not** leak the staging path here.

**Verdict:** kept as a **local-only**, harmless, conservative declaration backed
by the original history. **Not upstreamed** — there is no reproducible failure to
hand maintainers, and the upstream workflow runs fvsOL from source rather than
installing it as a library (so the lazy-load build the error class concerns never
runs for them).
