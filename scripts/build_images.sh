#!/usr/bin/env bash
# Build the FVS deliverable images and smoke-test them in-image.
#
# Runs identically in CI and on a workstation/lab PC: docker and podman are
# CLI-compatible, so set ENGINE=podman on a podman host. Build context is the
# repo root. This is the single source of truth for the build commands -- the
# GitHub Actions workflow just calls this script.
#
# Usage:
#   [ENGINE=podman] [FVS_VARIANT=ie] [FVS_BASE=source] [TARGETS="webgui cluster"] \
#     scripts/build_images.sh
#
# Env:
#   ENGINE       docker (default) or podman
#   FVS_VARIANT  FVS variant                              (default ie)
#   FVS_BASE     source (default; compile from vendor/fvs) or ghcr
#   TARGETS      space-separated targets to build         (default "webgui cluster")
#   TAG_PREFIX   image name prefix                        (default fvs)
#   SMOKE        1 (default) run smoke_test.R in each built image, 0 to skip
#   TESTS        1 (default) run tests/run_tests.R in each built image, 0 to skip
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENGINE="${ENGINE:-docker}"
FVS_VARIANT="${FVS_VARIANT:-ie}"
FVS_BASE="${FVS_BASE:-source}"
TARGETS="${TARGETS:-webgui cluster}"
TAG_PREFIX="${TAG_PREFIX:-fvs}"
SMOKE="${SMOKE:-1}"

command -v "$ENGINE" >/dev/null 2>&1 || { echo "ERROR: '$ENGINE' not found on PATH" >&2; exit 1; }

# target -> image name (webgui = GUI; cluster = HPC engine + R/rFVS)
img_for() {
  case "$1" in
    webgui)  echo "${TAG_PREFIX}-webgui:${FVS_VARIANT}" ;;
    cluster) echo "${TAG_PREFIX}-engine:${FVS_VARIANT}" ;;
    *)       echo "${TAG_PREFIX}-${1}:${FVS_VARIANT}" ;;
  esac
}

for t in $TARGETS; do
  tag="$(img_for "$t")"
  echo ">>> build target=$t -> $tag  (FVS_VARIANT=$FVS_VARIANT FVS_BASE=$FVS_BASE)"
  "$ENGINE" build -f docker/Dockerfile --target "$t" \
    --build-arg "FVS_VARIANT=${FVS_VARIANT}" \
    --build-arg "FVS_BASE=${FVS_BASE}" \
    -t "$tag" .
done

# Smoke test inside each built image. smoke_test.R is baked into the image (at
# /opt/fvs/smoke_test.R), so it runs with no bind mount -- avoids host bind-mount
# permission issues (SELinux/UID under podman). It self-skips the fvsOL guards
# where fvsOL is absent (the cluster image), so the same gate works for both.
if [ "$SMOKE" = "1" ]; then
  for t in $TARGETS; do
    tag="$(img_for "$t")"
    echo ">>> smoke test in $tag"
    "$ENGINE" run --rm "$tag" Rscript /opt/fvs/smoke_test.R
  done
fi

# R test suite inside each built image: pure-R unit tests (data-path guard +
# keyword writer) plus the engine integration test (runs FVS on the upstream
# iet01 'ie' example). Baked at /opt/fvs/tests, so no bind mount needed. Gating
# here means publish.yaml won't push an image whose engine/workflows regress.
if [ "${TESTS:-1}" = "1" ]; then
  for t in $TARGETS; do
    tag="$(img_for "$t")"
    echo ">>> R test suite in $tag"
    "$ENGINE" run --rm "$tag" Rscript /opt/fvs/tests/run_tests.R
  done
fi

echo ">>> done"
