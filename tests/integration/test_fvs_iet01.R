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

  # the main text output (.out preferred, else .sum / console), as one vector
  outfiles <- list.files(run, pattern = "\\.(out|sum)$", full.names = TRUE)
  outtxt   <- unlist(lapply(outfiles, readLines, warn = FALSE))

  # FVS STOP codes 0/10/20 are all non-fatal completions (see docs/HELLGATE_FVS.md).
  check("fvs/iet01-exit", isTRUE(st %in% c(0L, 10L, 20L)))

  # it must produce a non-empty main output file (.out or run summary .sum)
  check("fvs/iet01-output",
        length(outfiles) >= 1 && any(file.info(outfiles)$size > 0))

  # and the run must not report a FATAL error in the main output
  check("fvs/iet01-no-fatal",
        !any(grepl("FATAL", outtxt, ignore.case = TRUE)))

  # FVS actually ingested our keyword file (the stand id is echoed in the run
  # header) -- guards against a boilerplate-only / empty run passing the checks
  # above. S248112 is the iet01 stand id (see tests/fixtures/fvs_ie/iet01.key).
  check("fvs/iet01-read-stand", any(grepl("S248112", outtxt, fixed = TRUE)))

  # The real correctness signal: FVS must have computed a multi-cycle PROJECTION
  # with non-zero stand metrics, not merely exited 0 (it returns 0 even on
  # per-stand errors). iet01.key sends its summary to the .sum text file via
  # ECHOSUM (it does not request DB output -- FVSOut.db holds only admin tables),
  # so we parse the .sum. Format-tolerant by design: a "cycle row" is any line
  # whose first token is a 4-digit projection year (1990..2100) followed by
  # several numeric fields; we require >= 2 such rows (multiple cycles) and at
  # least one large positive metric (TPA/BA are tens-hundreds). No fixed columns,
  # so it survives FVS layout/version changes.
  sumf <- list.files(run, pattern = "\\.sum$", full.names = TRUE)
  cycle_metrics <- function(line) {
    toks <- strsplit(trimws(line), "\\s+")[[1]]
    if (length(toks) < 6) return(numeric(0))
    if (!grepl("^(19|20)[0-9]{2}$", toks[1])) return(numeric(0))
    nums <- suppressWarnings(as.numeric(toks[-1]))
    nums[!is.na(nums)]
  }
  check("fvs/iet01-projection", {
    if (!length(sumf)) FALSE else {
      rows <- Filter(length, lapply(readLines(sumf[1], warn = FALSE), cycle_metrics))
      length(rows) >= 2 && any(vapply(rows, function(v) any(v > 1), logical(1)))
    }
  })

  # --- diagnostics (temporary, calibration): output files + .sum head, so the
  # .sum parse above can be eyeballed against FVS's real format. Never fails. ---
  cat("  --- iet01 run: exit =", st, "; output files ---\n")
  for (f in list.files(run, full.names = TRUE))
    cat(sprintf("      %9.0f  %s\n", file.info(f)$size, basename(f)))
  if (length(sumf)) {
    cat("  --- iet01.sum (first 20 lines) ---\n")
    for (ln in utils::head(readLines(sumf[1], warn = FALSE), 20L))
      cat("      |", ln, "\n")
  }
})()
