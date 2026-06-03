#!/bin/sh
# Launch the FVS WebGUI as the uid/gid that OWNS the bind-mounted /work, so a
# forester can create + save projects with the plain `docker run -v <host>:/work`
# command -- no --user flag needed. The image's baked-in non-root `fvs` user
# can't write a host-owned bind mount, so fvsOL's dir.create()/setwd() for a new
# project fails with "Permission denied".
#
# Docker Desktop presents the mount owner differently per host:
#   - Linux:  the host user's real uid -> run as that uid (files owned by them).
#   - macOS:  the mount shows up root-owned (uid 0), but root CAN write it and
#             Docker Desktop maps container-root writes back to the host user.
# In BOTH cases the *mount owner* can write, so we always drop to it. When that
# owner is root (macOS, an unmounted /work, the CI smoke test, or a named
# volume), we run as root -- which writes fine. (Do NOT fall back to `fvs` on
# uid 0: that is exactly the macOS case, and `fvs` can't write the mount.)
set -eu

uid="$(stat -c %u /work 2>/dev/null || echo 0)"
gid="$(stat -c %g /work 2>/dev/null || echo 0)"

exec gosu "${uid}:${gid}" "$@"
