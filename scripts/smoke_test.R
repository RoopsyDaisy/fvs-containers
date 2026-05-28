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
  library(fvsOL)
  library(fs)
  library(DBI)
  library(RSQLite)
})

results <- list()
check <- function(name, expr) {
  ok <- tryCatch(isTRUE(expr), error = function(e) {
    message(sprintf("  [%s] error: %s", name, conditionMessage(e)))
    FALSE
  })
  results[[name]] <<- ok
  cat(sprintf("GUARD %-22s %s\n", name, if (ok) "PASS" else "FAIL"))
}

# Guard 1 - fs drift: fvsOL calls dir_exists()/dir_ls() (fs) by bare name in
# getVolumes2(); they must resolve at runtime or the session aborts on startup.
check("fs/getVolumes2", {
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

failed <- names(Filter(isFALSE, results))
if (length(failed)) {
  cat(sprintf("\nSMOKE TEST FAILED: %s\n", paste(failed, collapse = ", ")))
  quit(status = 1)
}
cat("\nSMOKE TEST PASSED\n")
