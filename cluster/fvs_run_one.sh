#!/usr/bin/env bash
# Run FVS on a single keyword file in an isolated per-run output directory.
#
# Shared by the SLURM array job (fvs_array.sbatch) and the no-scheduler local
# runner (run_local.sh) so the cluster and local code paths stay identical.
#
# Engine selection (first that applies):
#   SIF set      -> apptainer exec "$SIF" FVS<variant>   (HPC / Hellgate)
#   FVS_BIN set  -> "$FVS_BIN"/FVS<variant>              (native, e.g. dev container)
#   otherwise    -> FVS<variant> on PATH
#
# FVS reads the keyword *filename* (not path) on stdin and writes its outputs
# (FVSOut.db, .sum, .trl, ...) into the current directory, so each run gets its
# own directory and reused output names never collide.
#
# Usage: fvs_run_one.sh <keyword_file> <output_root>
set -euo pipefail

KEY="$(readlink -f "${1:?keyword file}")"
OUTROOT="${2:?output root}"
VARIANT="${VARIANT:-ie}"
PRG="FVS${VARIANT}"
[ -n "${FVS_BIN:-}" ] && FVS_BIN="$(readlink -f "$FVS_BIN")"

RUNDIR="${OUTROOT}/$(basename "${KEY%.*}")"
mkdir -p "$RUNDIR"

# Optionally stage shared, read-only input files (e.g. an inventory database
# referenced by the keyword file's DSNIn, treelists) into the run dir so
# relative references resolve. FVS_INPUT is a space-separated list of paths.
# Symlinks keep it cheap and allow concurrent readers across array tasks.
if [ -n "${FVS_INPUT:-}" ]; then
  for f in ${FVS_INPUT}; do ln -sf "$(readlink -f "$f")" "$RUNDIR/"; done
fi

cp "$KEY" "$RUNDIR/"
cd "$RUNDIR"
base="$(basename "$KEY")"

if [ -n "${SIF:-}" ]; then
  echo "$base" | apptainer exec "$SIF" "$PRG"
else
  echo "$base" | "${FVS_BIN:+$FVS_BIN/}$PRG"
fi
