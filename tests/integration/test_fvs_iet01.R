# Integration: run the real FVS engine on the upstream iet01 'ie' example
# (tests/fixtures/fvs_ie). Exercises the same `FVS<variant> --keywordfile=`
# invocation the cluster batch runner (cluster/fvs_run_one.sh) uses, against a
# guaranteed-valid, variant-matched fixture. Self-skips where the engine isn't
# present, so the unit layer still runs on a plain R host (lab PC). Uses
# check()/skip()/FIXTURE_DIR from run_tests.R. Immediately-invoked function (not
# local()) so the early-return skips and setwd()'s on.exit() work.
(function() {
  variant <- Sys.getenv("FVS_VARIANT", "ie")
  prog    <- paste0("FVS", variant)

  bd  <- Sys.getenv("FVS_BIN", "")
  exe <- if (nzchar(bd) && file.exists(file.path(bd, prog))) file.path(bd, prog)
         else { w <- Sys.which(prog); if (nzchar(w)) unname(w) else "" }

  if (!nzchar(exe))      return(skip("fvs/iet01-run", paste(prog, "not on PATH/FVS_BIN")))
  if (variant != "ie")   return(skip("fvs/iet01-run", "fixture is the 'ie' variant"))

  fxd <- file.path(FIXTURE_DIR, "fvs_ie")
  run <- tempfile("iet01_"); dir.create(run)
  file.copy(file.path(fxd, c("iet01.key", "iet01.tre")), run)  # .tre must sit next to .key
  old <- setwd(run); on.exit(setwd(old), add = TRUE)

  st <- suppressWarnings(system2(exe, "--keywordfile=iet01.key",
                                 stdout = "iet01.console", stderr = "iet01.console"))

  # FVS STOP codes 0/10/20 are all non-fatal completions (see docs/HELLGATE_FVS.md).
  check("fvs/iet01-exit", isTRUE(st %in% c(0L, 10L, 20L)))

  # it must produce a non-empty main output file (.out or run summary .sum)
  check("fvs/iet01-output", {
    out <- list.files(run, pattern = "\\.(out|sum)$", full.names = TRUE)
    length(out) >= 1 && any(file.info(out)$size > 0)
  })

  # and the run must not report a FATAL error in the main output
  check("fvs/iet01-no-fatal", {
    f <- list.files(run, pattern = "\\.out$", full.names = TRUE)
    length(f) == 0 ||
      !any(grepl("FATAL", readLines(f[1], warn = FALSE), ignore.case = TRUE))
  })
})()
</content>
