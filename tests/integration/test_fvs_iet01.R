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

  # The real correctness signal: FVS writes its results to an output SQLite DB
  # (FVSOut.db). Assert it actually computed a multi-cycle projection with
  # non-zero stand metrics -- not just that the process exited 0. Table/column
  # names are discovered at runtime (FVS_Summary vs _Summary2; Tpa/BA casing) so
  # we don't hard-code a schema. Skips only if RSQLite is unavailable.
  dbf <- list.files(run, pattern = "\\.db$", full.names = TRUE)
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) {
    skip("fvs/iet01-projection", "DBI/RSQLite not installed")
  } else if (!length(dbf)) {
    check("fvs/iet01-projection", FALSE)        # FVSOut.db is expected; absence is a real failure
  } else {
    con  <- DBI::dbConnect(RSQLite::SQLite(), dbf[1])
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    tbls <- DBI::dbListTables(con)
    sumt <- grep("^FVS_Summary", tbls, ignore.case = TRUE, value = TRUE)
    check("fvs/iet01-projection", {
      if (!length(sumt)) FALSE else {
        d  <- DBI::dbGetQuery(con, sprintf('SELECT * FROM "%s"', sumt[1]))
        cn <- toupper(names(d))
        col <- function(nm) { j <- which(cn == nm)
          if (length(j)) suppressWarnings(as.numeric(d[[j[1]]])) else numeric(0) }
        tpa <- col("TPA"); ba <- col("BA")
        nrow(d) >= 2 && length(tpa) && length(ba) &&
          any(tpa > 0, na.rm = TRUE) && any(ba > 0, na.rm = TRUE)
      }
    })
    # diagnostic: DB schema, so any name mismatch is debuggable in the same run
    cat("  --- FVSOut.db tables:", paste(tbls, collapse = ", "), "---\n")
    if (length(sumt)) {
      d <- DBI::dbGetQuery(con, sprintf('SELECT * FROM "%s"', sumt[1]))
      cat("  ---", sumt[1], "cols:", paste(names(d), collapse = ","), "\n")
      cat("  ---", sumt[1], "rows:", nrow(d), "\n")
    }
  }

  # --- text diagnostics (temporary, calibration): bounded dump of the .out ---
  cat("  --- iet01 run: exit =", st, "; output files ---\n")
  for (f in list.files(run, full.names = TRUE))
    cat(sprintf("      %9.0f  %s\n", file.info(f)$size, basename(f)))
})()
