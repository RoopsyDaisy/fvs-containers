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
  # so we parse the .sum. Each data row is one projection cycle:
  #   <4-digit year> <age> <TPA> <BA> ... (~24 numeric fields); case headers
  #   start with -999 and are skipped. Format-tolerant: we match by the
  #   leading-year shape and read TPA/BA positionally, so it survives column
  #   drift across FVS versions. iet01 projects S248112 over 11 cycles
  #   (1990..2090), so we require several cycles with TPA>0 and BA>0.
  sumf <- list.files(run, pattern = "\\.sum$", full.names = TRUE)
  cycle_row <- function(line) {                       # numeric fields, or NULL if not a cycle row
    toks <- strsplit(trimws(line), "\\s+")[[1]]
    if (length(toks) < 6 || !grepl("^(19|20)[0-9]{2}$", toks[1])) return(NULL)
    suppressWarnings(as.numeric(toks))                # [1]=year [2]=age [3]=TPA [4]=BA ...
  }
  check("fvs/iet01-projection", {
    if (!length(sumf)) FALSE else {
      rows <- Filter(Negate(is.null),
                     lapply(readLines(sumf[1], warn = FALSE), cycle_row))
      yrs <- vapply(rows, `[`, numeric(1), 1L)
      tpa <- vapply(rows, `[`, numeric(1), 3L)
      ba  <- vapply(rows, `[`, numeric(1), 4L)
      # >= 3 distinct projection cycles, and most carry positive stand metrics.
      # "most" (not all): the keyfile includes a shelterwood prescription that
      # can drive a cycle's stand very low -- a degenerate "ran but computed
      # nothing" run instead yields no rows or all-zeros, which this still fails.
      length(rows) >= 3 && length(unique(yrs)) >= 3 &&
        mean(tpa > 0, na.rm = TRUE) > 0.5 && mean(ba > 0, na.rm = TRUE) > 0.5
    }
  })

  # one-line provenance in the log (engine version + run id come from .sum row 1)
  cat(sprintf("  iet01: exit=%s, %d output files, .sum=%s bytes\n",
              st, length(list.files(run)),
              if (length(sumf)) file.info(sumf[1])$size else 0))
})()
