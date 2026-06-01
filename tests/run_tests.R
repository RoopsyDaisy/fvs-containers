#!/usr/bin/env Rscript
# R test harness for the FVS container repo.
#
# Plain base-R, matching scripts/smoke_test.R style (no testthat dependency, so
# nothing new lands in renv.lock / the image). Validates the FVS *engine*:
#   - integration/ runs the real FVS engine on the upstream iet01 'ie' example;
#                  self-skips where FVS<variant> isn't on PATH/FVS_BIN.
# (The R-workflow unit tests + their code moved to the fvs-hpc-toolkit repo.)
#
# Exits non-zero if any check fails. Baked into the deliverable image at
# /opt/fvs/tests and run by scripts/build_images.sh, so the GHCR publish is
# gated on these tests (publish.yaml builds + tests before pushing).
#
# Run locally from a clone:  Rscript tests/run_tests.R
# Run in a built image:      <engine> run --rm <image> Rscript /opt/fvs/tests/run_tests.R

get_script_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}
TESTS_DIR   <- get_script_dir()
# repo root in a clone, /opt/fvs in the image -- both mirror <root>/scripts/... .
REPO_ROOT   <- normalizePath(file.path(TESTS_DIR, ".."))
FIXTURE_DIR <- file.path(TESTS_DIR, "fixtures")

# Shared assertion harness (same contract as smoke_test.R::check).
.results <- list()
check <- function(name, expr) {
  ok <- tryCatch(isTRUE(expr), error = function(e) {
    message(sprintf("  [%s] error: %s", name, conditionMessage(e))); FALSE
  })
  .results[[name]] <<- ok
  cat(sprintf("CHECK %-30s %s\n", name, if (ok) "PASS" else "FAIL"))
}
skip <- function(name, why)
  cat(sprintf("CHECK %-30s SKIP (%s)\n", name, why))

# Run every test file (each calls check()/skip() at source time). This repo's
# in-image suite validates the FVS *engine*; the R-workflow unit tests + the code
# they exercise moved to fvs-hpc-toolkit (tested there against the published image).
test_files <- list.files(file.path(TESTS_DIR, "integration"),
                         pattern = "\\.R$", full.names = TRUE)
for (f in test_files) {
  cat(sprintf("\n# %s\n", sub(paste0(REPO_ROOT, "/?"), "", f)))
  source(f)
}

failed <- names(Filter(isFALSE, .results))
cat(sprintf("\n%d checks, %d failed\n", length(.results), length(failed)))
if (length(failed)) {
  cat(sprintf("TESTS FAILED: %s\n", paste(failed, collapse = ", ")))
  quit(status = 1)
}
cat("ALL TESTS PASSED\n")
