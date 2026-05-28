#!/usr/bin/env bash
#
# Build one FVS variant from source as shared libraries + executable.
#
# Produces, in <out_bin_dir>:
#   FVS<variant>            the command-line executable
#   libFVS_<variant>.so     the Fortran engine (links the two below)
#   libFVSsql.so            SQLite I/O + the Cfvs* R-interface symbols
#   libFVSfofem.so          Fire & Fuels (FOFEM) C library
#   FVS<variant>.so         symlink -> libFVS_<variant>.so, for rFVS/R (see docs/BUILD.md)
#
# The FVS source tree is left clean afterwards (all generated build files removed).
#
# Usage: build_fvs.sh <fvs_src_dir> <variant> <out_bin_dir> [jobs]
#   fvs_src_dir   checkout of USDAForestService/ForestVegetationSimulator
#                 (with the NVEL submodule populated under volume/NVEL)
#   variant       lowercase variant code matching bin/FVS<variant>_sourceList.txt
#                 e.g. ie (Inland Empire), pn, so, ...
#   out_bin_dir   where to place the built artifacts
#   jobs          parallel compile jobs (default: nproc)
#
set -euo pipefail

# Absolutise paths up front: the build cd's into the source tree, so relative
# arguments would break partway through.
FVS_SRC="$(cd "${1:?path to FVS source tree}" && pwd)"
VARIANT="${2:?variant code, e.g. ie}"
OUT_BIN="$3"; : "${OUT_BIN:?output bin directory}"
mkdir -p "${OUT_BIN}"; OUT_BIN="$(cd "${OUT_BIN}" && pwd)"
JOBS="${4:-$(nproc)}"

PRG="FVS${VARIANT}"
BIN_DIR="${FVS_SRC}/bin"
CMAKEDIR="${BIN_DIR}/${PRG}_CmakeDir"

[ -f "${BIN_DIR}/${PRG}_sourceList.txt" ] || { echo "ERROR: bin/${PRG}_sourceList.txt not found; is '${VARIANT}' a valid variant?" >&2; exit 1; }
[ -f "${FVS_SRC}/volume/NVEL/wdbkwtdata.inc" ] || { echo "ERROR: volume/NVEL not populated; run 'git submodule update --init --recursive'." >&2; exit 1; }

# Leave the source tree exactly as we found it, even on failure.
cleanup() {
  cd "${BIN_DIR}" 2>/dev/null || return 0
  [ -f CMakeLists.txt.orig ] && mv -f CMakeLists.txt.orig CMakeLists.txt
  rm -rf "${CMAKEDIR}" CMakeCache.txt CMakeFiles cmake_install.cmake Makefile
}
trap cleanup EXIT

cd "${BIN_DIR}"

# Restrict the all-variant GLOB to just this variant so cmake doesn't configure
# all ~25 variants.
cp CMakeLists.txt CMakeLists.txt.orig
sed -i "s|file(GLOB tobuild FVS\*_sourceList.txt)|file(GLOB tobuild ${PRG}_sourceList.txt)|" CMakeLists.txt

# 1. Configure: generates ${PRG}_CmakeDir/ and runs cmake inside it (no compile yet).
cmake -G "Unix Makefiles" .

# 2. UNDOCUMENTED STEP: the NVEL include wdbkwtdata.inc is not auto-discovered.
#    CMake only adds .h/.F77 directories to the include path, never .inc dirs, so
#    ie/vols.f cannot find it. The build dir is on the include path, so copy it in.
cp "${FVS_SRC}/volume/NVEL/wdbkwtdata.inc" "${CMAKEDIR}/"

# 3. Compile.
make -C "${CMAKEDIR}" -j"${JOBS}"

# 4. Collect artifacts.
cp "${CMAKEDIR}/${PRG}" "${OUT_BIN}/"
cp "${CMAKEDIR}"/lib*.so "${OUT_BIN}/"

# 5. rFVS dyn.load()s a library named "<PRG>.so". Point it at the Fortran engine;
#    its NEEDED deps (libFVSsql.so) supply the Cfvs* API symbols rFVS calls.
ln -sf "libFVS_${VARIANT}.so" "${OUT_BIN}/${PRG}.so"

echo "Built ${PRG} -> ${OUT_BIN}"
ls -l "${OUT_BIN}"
