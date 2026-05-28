#!/usr/bin/env bash
#
# Build one FVS variant from source using the fvs-build Meson overlay.
#
# Produces, in <out_bin_dir>:
#   FVS<variant>       the standalone command-line executable
#   FVS<variant>.so    the self-contained embedder shared library for rFVS/PyFVS
#                      (no lib prefix; contains the Cfvs* R-interface symbols)
#
# This replaces the previous hand-rolled CMake build (with its per-variant GLOB
# edit and NVEL wdbkwtdata.inc workaround); the Meson overlay handles those.
#
# Usage: build_fvs.sh <fvs_src_dir> <variant> <out_bin_dir> [overlay_dir] [jobs]
#   fvs_src_dir   checkout of USDAForestService/ForestVegetationSimulator
#                 (with the NVEL nested submodule populated under volume/NVEL)
#   variant       lowercase variant code, e.g. ie (Inland Empire), pn, so, ...
#   out_bin_dir   where to place the built artifacts
#   overlay_dir   the fvs-build Meson overlay (default: sibling of fvs_src_dir,
#                 i.e. <dirname fvs_src_dir>/fvs-build)
#   jobs          parallel compile jobs (default: nproc)
#
set -euo pipefail

FVS_SRC="$(cd "${1:?path to FVS source tree}" && pwd)"
VARIANT="${2:?variant code, e.g. ie}"
OUT_BIN="${3:?output bin directory}"; mkdir -p "${OUT_BIN}"; OUT_BIN="$(cd "${OUT_BIN}" && pwd)"
OVERLAY="$(cd "${4:-$(dirname "${FVS_SRC}")/fvs-build}" && pwd)"
JOBS="${5:-$(nproc)}"

PRG="FVS${VARIANT}"
[ -f "${FVS_SRC}/bin/${PRG}_sourceList.txt" ] || { echo "ERROR: bin/${PRG}_sourceList.txt not found; is '${VARIANT}' a valid variant?" >&2; exit 1; }
[ -f "${FVS_SRC}/volume/NVEL/wdbkwtdata.inc" ] || { echo "ERROR: volume/NVEL not populated; run 'git submodule update --init --recursive'." >&2; exit 1; }
[ -f "${OVERLAY}/meson.build" ] || { echo "ERROR: fvs-build overlay not found at ${OVERLAY}; is the vendor/fvs-build submodule populated?" >&2; exit 1; }

# Stray *.mod files committed/left in the source tree corrupt the build
# ("Reading module ... Unexpected EOF"); fvs-build's CI deletes them too.
find "${FVS_SRC}" -name '*.mod' -delete

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

meson setup "${BUILD_DIR}" "${OVERLAY}" \
  -Dfvs_source_dir="${FVS_SRC}" -Dvariants="${VARIANT}" -Dprofile=reference
meson compile -C "${BUILD_DIR}" -j "${JOBS}"

cp "${BUILD_DIR}/${PRG}" "${BUILD_DIR}/${PRG}.so" "${OUT_BIN}/"

echo "Built ${PRG} -> ${OUT_BIN}"
ls -l "${OUT_BIN}/${PRG}" "${OUT_BIN}/${PRG}.so"
