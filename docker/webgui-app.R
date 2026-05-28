# Headless launcher for the FVSOnline (fvsOL) WebGUI inside a container.
#
# fvsOL() returns a Shiny app object (it wraps shinyApp()); we serve it on all
# interfaces so a host browser (e.g. macOS via OrbStack/Docker Desktop port
# forwarding) can reach it. The working directory is the fvsOL "project" dir;
# if it has no FVS_Data.db, fvsOL loads its bundled training data.
suppressMessages(library(fvsOL))
# fvsOL's getVolumes2() (local mode) calls fs::dir_exists/dir_ls by bare name
# without importing fs, so fs must be attached or the session aborts on startup.
suppressMessages(library(fs))

fvsBin <- Sys.getenv("FVS_BIN", "/opt/fvs/bin")
port   <- as.integer(Sys.getenv("PORT", "3838"))
stopifnot(dir.exists(fvsBin))

app <- fvsOL(fvsBin = fvsBin)
shiny::runApp(app, host = "0.0.0.0", port = port, launch.browser = FALSE)
