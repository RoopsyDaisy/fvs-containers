#!/bin/sh
# Launch the FVS WebGUI as the uid/gid that owns the bind-mounted /work, so a
# forester can create + save projects in their host folder with the plain
# `docker run ... -v <host>:/work` command -- no --user flag needed.
#
# Why: Docker Desktop (macOS/Linux) presents the *host* owner on the bind mount,
# and the image's baked-in non-root `fvs` user can't write a foreign-owned mount
# -- so fvsOL's dir.create()/setwd() for a new project fails with "Permission
# denied". Matching the process uid to the mount owner fixes it transparently.
#
# When /work is unmounted or root-owned (e.g. the CI smoke test, or a named
# volume), fall back to the baked-in `fvs` user rather than running as root.
set -eu

uid="$(stat -c %u /work 2>/dev/null || echo 0)"
gid="$(stat -c %g /work 2>/dev/null || echo 0)"
if [ "$uid" = "0" ]; then
  uid="$(id -u fvs)"
  gid="$(id -g fvs)"
fi

exec gosu "${uid}:${gid}" "$@"
