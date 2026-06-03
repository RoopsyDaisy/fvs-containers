# Shared launcher logic for the fvsOL WebGUI, factored out so smoke_test.R can
# unit-test it without starting the Shiny server. Sourced by docker/webgui-app.R
# (the real launcher) and by the smoke test's webgui/project-persistence guard.

# Pick the fvsOL project sub-folder to launch in, under `master`, and return its
# path (created if needed).
#
# fvsOL's project model: `master` holds one sub-folder per project and you run
# INSIDE a project -- "New Project" does setwd("..") + dir.create (i.e. creates a
# SIBLING of the current project), and getProjectList() lists ../*/projectId.txt.
# So the launch dir's PARENT must be `master`; if we launched in `master` itself,
# new projects would escape to master's parent (the container's ephemeral root /)
# and be lost when the --rm container stops. INVARIANT: dirname(result) == master.
#
# Resumes the most-recently-used existing project under `master`, else seeds
# "MyProject" (fvsOL fills an empty project dir with its bundled training data).
webgui_project_dir <- function(master) {
  dir.create(master, recursive = TRUE, showWarnings = FALSE)
  projects <- Filter(function(d) file.exists(file.path(d, "projectId.txt")),
                     list.dirs(master, recursive = FALSE))
  project <- if (length(projects)) {
    projects[[which.max(file.mtime(projects))]]
  } else {
    file.path(master, "MyProject")
  }
  dir.create(project, recursive = TRUE, showWarnings = FALSE)
  project
}
