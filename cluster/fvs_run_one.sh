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
# FVS runs via `--keywordfile=<name>`: it derives the auxiliary filenames
# (.tre tree data, .out, .trl) from the keyword base name and runs
# non-interactively. (Reading the keyword name on stdin instead would drop FVS
# into interactive file-name prompting for any keyword file that isn't fully
# database-self-contained, so --keywordfile is the robust choice for both
# database-style and legacy flat-file keyword files.) FVS writes its outputs
# (FVSOut.db, .out, .trl, ...) into the current directory, so each run gets its
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

# Flat-file tree input: FVS reads tree records from "<base>.tre", referenced only
# by the keyword file's own base name, so stage a sibling .tre next to the .key.
tre="${KEY%.*}.tre"
[ -f "$tre" ] && cp "$tre" "$RUNDIR/"

cd "$RUNDIR"
base="$(basename "$KEY")"

rc=0
if [ -n "${SIF:-}" ]; then
  apptainer exec "$SIF" "$PRG" --keywordfile="$base" </dev/null || rc=$?
else
  "${FVS_BIN:+$FVS_BIN/}$PRG" --keywordfile="$base" </dev/null || rc=$?
fi

# FVS reports completion via its STOP code as the process exit status: 0, 20
# (normal completion) and 10 (completed with warnings, e.g. benign SDI
# adjustments) are all success. Any other code is a genuine failure. (Per-stand
# data/keyword problems are logged to the FVS_Error table in the output DB, not
# the exit code -- a clean STOP 20 can still carry FVS_Error rows.)
case "$rc" in
  0|10|20) ;;
  *) exit "$rc" ;;
esac
