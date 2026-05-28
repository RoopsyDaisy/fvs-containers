#!/usr/bin/env Rscript
# Headless regression smoke test for the FVS WebGUI (fvsOL) environment.
#
# Pins the dependency-drift bugs that have broken session startup so a rebuild
# fails loudly instead of waiting for a human to open the GUI. These are fast,
# deterministic, browser-free checks of the exact failure points we hit; the
# faithful end-to-end (boot + click-through an FVS run) is the separate
# shinytest2 + Chromium suite.
#
# Exits non-zero if any guard fails.

suppressMessages({
  library(DBI)
  library(RSQLite)
})
# fvsOL only exists in the WebGUI image; rFVS in both WebGUI and cluster images.
# Load conditionally so this one smoke test runs in any FVS image (the fvsOL
# guards self-skip where fvsOL is absent, e.g. the cluster image).
have_fvsOL <- requireNamespace("fvsOL", quietly = TRUE)
have_rFVS  <- requireNamespace("rFVS",  quietly = TRUE)
if (have_fvsOL) suppressMessages({ library(fvsOL); library(fs) })

results <- list()
check <- function(name, expr) {
  ok <- tryCatch(isTRUE(expr), error = function(e) {
    message(sprintf("  [%s] error: %s", name, conditionMessage(e)))
    FALSE
  })
  results[[name]] <<- ok
  cat(sprintf("GUARD %-22s %s\n", name, if (ok) "PASS" else "FAIL"))
}

# Locate the FVS bin directory (the dir holding FVS<variant> + FVS<variant>.so):
# FVS_BIN env, else PATH, else the dev-container fallback. "" if not found.
fvs_bin_dir <- function(variant = Sys.getenv("FVS_VARIANT", "ie")) {
  prog <- paste0("FVS", variant)
  bd   <- Sys.getenv("FVS_BIN", "")
  if (nzchar(bd) && file.exists(file.path(bd, prog))) return(bd)
  w <- Sys.which(prog)
  if (nzchar(w)) return(dirname(unname(w)))
  alt <- file.path(".devcontainer", "fvs-bin")  # dev container fallback
  if (file.exists(file.path(alt, prog))) return(normalizePath(alt))
  ""
}

# Read FVS's build version from the startup banner ("FVS VARIANT -- RV:<version>").
# Returns the version string, or NA if FVS isn't runnable. Feeds a dummy keyword
# name so FVS prints the banner, runs in a temp dir to avoid stray files, and
# strips the NUL bytes FVS embeds in the banner (they otherwise truncate R's
# captured strings at the first NUL).
fvs_version <- function(variant = Sys.getenv("FVS_VARIANT", "ie")) {
  bd <- fvs_bin_dir(variant)
  if (!nzchar(bd)) return(NA_character_)
  exe <- file.path(bd, paste0("FVS", variant))
  cmd <- sprintf("cd %s && echo __ver__ | %s 2>&1 | tr -d '\\000'",
                 shQuote(tempdir()), shQuote(exe))
  out  <- suppressWarnings(system(cmd, intern = TRUE))
  line <- grep("RV:", out, value = TRUE)
  if (!length(line)) return(NA_character_)
  sub(".*RV:([0-9A-Za-z.]+).*", "\\1", line[1])
}

# Guard 0 - rFVS present: both images need rFVS for the R-driven workflows
# (rFVS::fvsMakeKeyFile for batch generation, fvsInteractRun for the interactive
# track).
check("rFVS/present", have_rFVS)

# Guard 1 - fs drift (WebGUI only): fvsOL calls dir_exists()/dir_ls() (fs) by
# bare name in getVolumes2(); they must resolve at runtime or the session aborts
# on startup. Skipped where fvsOL isn't installed (e.g. the cluster image).
if (have_fvsOL) check("fs/getVolumes2", {
  v <- fvsOL:::getVolumes2()()
  is.character(v) && length(v) >= 1
})

# Guard 2 - RSQLite drift: fvsOL writes temp tables; the old
# dbWriteTable(conn, DBI::SQL("temp.X"), ...) form breaks on current RSQLite
# ("Named parameters not used in query"). The supported form must work and be
# readable via the temp schema.
check("rsqlite/temp-write", {
  con <- dbConnect(SQLite(), ":memory:")
  on.exit(dbDisconnect(con), add = TRUE)
  dbWriteTable(con, "Grps", data.frame(Stand_ID = "", Grp = ""),
               temporary = TRUE, overwrite = TRUE)
  nrow(dbGetQuery(con, "select * from temp.Grps")) >= 0
})

# Guard 3 - FVS engine present + version stamp: the FVS binary must be runnable
# and report its build version, so a rebuild proves the engine is wired up and
# records which version the WebGUI/cluster images carry (provenance + a check
# that both share the same engine).
check("fvs/version", {
  rv <- fvs_version()
  if (is.na(rv)) FALSE else { cat(sprintf("  FVS engine version RV:%s\n", rv)); TRUE }
})

# Guard 4 - rFVS can LOAD the engine: actually dyn.load the FVS<variant>.so
# embedder via rFVS::fvsLoad, not just check the rFVS package exists. The
# interactive workflow (fvsInteractRun) needs this, and a CLI-only image (e.g. a
# GHCR base that ships FVS<variant> but not FVS<variant>.so) would fail HERE while
# passing fvs/version -- so this is what validates the .so in any built image.
if (have_rFVS) check("rFVS/fvsLoad", {
  bd <- fvs_bin_dir()
  if (nzchar(bd)) {
    suppressMessages(rFVS::fvsLoad(
      fvsProgram = paste0("FVS", Sys.getenv("FVS_VARIANT", "ie")), bin = bd))
    exists(".FVSLOADEDLIBRARY", envir = .GlobalEnv)
  } else FALSE
})

failed <- names(Filter(isFALSE, results))
if (length(failed)) {
  cat(sprintf("\nSMOKE TEST FAILED: %s\n", paste(failed, collapse = ", ")))
  quit(status = 1)
}
cat("\nSMOKE TEST PASSED\n")
