# Headless launcher for the FVSOnline (fvsOL) WebGUI inside a container.
#
# fvsOL() returns a Shiny app object (it wraps shinyApp()); we serve it on all
# interfaces so a host browser (e.g. macOS via OrbStack/Docker Desktop port
# forwarding) can reach it.
#
# fvsOL's project model: a "master" directory holds one sub-folder per project,
# and you run INSIDE a project. So we launch in a project sub-folder of the
# master -- see webgui-launch.R::webgui_project_dir() for the why + the rule.
suppressMessages(library(fvsOL))
# fvsOL's getVolumes2() (local mode) calls fs::dir_exists/dir_ls by bare name
# without importing fs, so fs must be attached or the session aborts on startup.
suppressMessages(library(fs))

# Shared, unit-tested launcher logic (also exercised by smoke_test.R). Lives at
# /opt/fvs/ in the image, docker/ in the dev loop.
source(Filter(file.exists, c("/opt/fvs/webgui-launch.R", "docker/webgui-launch.R"))[1])

fvsBin <- Sys.getenv("FVS_BIN", "/opt/fvs/bin")
port   <- as.integer(Sys.getenv("PORT", "3838"))
stopifnot(dir.exists(fvsBin))

# Master dir = the persisted, writable host folder (/work bind mount in the
# image; FVS_WORK override for the dev loop). Launch inside a project under it so
# new projects land beside it under the master and persist on the host.
master <- Sys.getenv("FVS_WORK", getwd())
setwd(webgui_project_dir(master))

app <- fvsOL(fvsBin = fvsBin)
shiny::runApp(app, host = "0.0.0.0", port = port, launch.browser = FALSE)
