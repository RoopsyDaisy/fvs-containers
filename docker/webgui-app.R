# Headless launcher for the FVSOnline (fvsOL) WebGUI inside a container.
#
# fvsOL() returns a Shiny app object (it wraps shinyApp()); we serve it on all
# interfaces so a host browser (e.g. macOS via OrbStack/Docker Desktop port
# forwarding) can reach it.
#
# fvsOL's project model: a "master" directory holds one sub-folder per project,
# and you run INSIDE a project. "New Project" does setwd("..") + dir.create (a
# sibling), and getProjectList() lists ../*/projectId.txt. So we MUST launch
# inside a project sub-folder of the master -- if we launched in the master
# itself (the bind-mounted /work), "New Project" would escape to the master's
# PARENT (the container's ephemeral root, /) and be lost when the container stops.
suppressMessages(library(fvsOL))
# fvsOL's getVolumes2() (local mode) calls fs::dir_exists/dir_ls by bare name
# without importing fs, so fs must be attached or the session aborts on startup.
suppressMessages(library(fs))

fvsBin <- Sys.getenv("FVS_BIN", "/opt/fvs/bin")
port   <- as.integer(Sys.getenv("PORT", "3838"))
stopifnot(dir.exists(fvsBin))

# Master dir = the persisted, writable host folder that holds the projects. In
# the image that's /work (the bind mount, set as WORKDIR); FVS_WORK overrides it
# for other launch contexts (e.g. the devcontainer dev loop).
master <- Sys.getenv("FVS_WORK", getwd())
dir.create(master, recursive = TRUE, showWarnings = FALSE)

# Launch inside a project sub-folder: resume the most-recently-used one, else
# start "MyProject" fresh (fvsOL seeds an empty project dir with its bundled
# training FVS_Data.db). New projects the user creates then land beside it under
# the master and persist on the host.
projects <- Filter(function(d) file.exists(file.path(d, "projectId.txt")),
                   list.dirs(master, recursive = FALSE))
project  <- if (length(projects)) {
  projects[[which.max(file.mtime(projects))]]
} else {
  file.path(master, "MyProject")
}
dir.create(project, recursive = TRUE, showWarnings = FALSE)
setwd(project)

app <- fvsOL(fvsBin = fvsBin)
shiny::runApp(app, host = "0.0.0.0", port = port, launch.browser = FALSE)
