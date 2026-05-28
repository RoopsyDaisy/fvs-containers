# Running FVS at scale on an HPC cluster (Hellgate)

This directory packages the slim FVS engine image ([docker/Dockerfile.fvs](../docker/Dockerfile.fvs))
for batch use on an Apptainer + SLURM cluster such as the University of Montana's
**Hellgate** Research cluster. For interactive single-stand exploration use the
WebGUI instead (see the top-level run docs); the cluster path is for large
simulation campaigns — many keyword files run in parallel.

## 1. Build the image and convert to a `.sif`

On a workstation with a container runtime (e.g. the Johnson-lab PC with podman):

```bash
# Build the slim FVS engine image for the variant you need
podman build -f docker/Dockerfile.fvs -t fvs:ie --build-arg FVS_VARIANT=ie .

# Convert it to an Apptainer image
cluster/build_sif.sh                 # produces fvs_ie.sif
```

Copy `fvs_ie.sif` to the cluster (`scp fvs_ie.sif user@hellgate:~/fvs/`).

Alternatively, push the OCI image to a registry and pull it on the cluster:
`apptainer pull fvs_ie.sif docker://<registry>/fvs:ie`.

## 2. Stage inputs and build a manifest

Put your keyword files somewhere on the cluster filesystem and list them, one
per line. The array job runs line *N* on array task *N*.

```bash
ls inputs/*.key > keyfiles.txt
```

Each keyword file should reference its own input (inline `TREEDATA`, a `TREELIST`
file beside it, or a `DSNin` database). Outputs are written per-run, so reused
output names (`FVSOut.db`) don't collide.

If many keyword files share **one inventory database** (the typical "build a
batch in R" pattern), don't duplicate it — pass it via `FVS_INPUT` and the
runner symlinks it into each run directory so the keyword file's relative
`DSNin` resolves:

```bash
export FVS_INPUT="$PWD/inputs/FVS_Data.db"      # space-separated list if several
```

## 3. Submit the array job

```bash
sbatch --array=1-$(wc -l < keyfiles.txt)%50 \
       --export=SIF=$PWD/fvs_ie.sif,VARIANT=ie,MANIFEST=$PWD/keyfiles.txt,FVS_INPUT=$PWD/inputs/FVS_Data.db \
       cluster/fvs_array.sbatch
```

- `%50` throttles to 50 concurrent tasks — tune to your allocation.
- Add `--account=...`/`--partition=...` per Hellgate's policy.
- Drop `FVS_INPUT=...` if each keyword file is self-contained.
- Outputs land in `runs/<keyfile-name>/`; logs in `logs/fvs_<jobid>_<taskid>.{out,err}`.

The job runs `FVS<variant>` inside the container with the keyword filename on
stdin; Apptainer bind-mounts the working directory, so all FVS output files
appear on the host filesystem under each run directory.

## 4. Test the batch locally (no SLURM / Apptainer)

`run_local.sh` runs the same per-task logic (`fvs_run_one.sh`) sequentially
against a **native** `FVS<variant>` binary — useful for validating a batch on a
workstation, in the dev container, or in CI before submitting to the cluster:

```bash
FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT="$PWD/inputs/FVS_Data.db" \
  cluster/run_local.sh keyfiles.txt runs
```

It reports `[ok]`/`[FAIL] (exit N)` per keyword file and exits non-zero if any
run failed. (Verified locally: a batch of keyword files each produces its own
isolated `runs/<name>/` with a populated output DB and no collisions.)

## Notes

- The per-task work (isolated run dir, stage `FVS_INPUT`, run FVS on the
  keyword file via stdin) lives in `fvs_run_one.sh`, shared by both the SLURM
  array job and `run_local.sh` so the cluster and local paths stay identical —
  only the engine differs (`apptainer exec` vs the native binary).
- Apptainer on Hellgate aliases `singularity`; either command works.
- The `.sif` is variant-specific (it contains `FVSie`). Build one `.sif` per
  variant you need, or build a multi-variant image and set `VARIANT` accordingly.
- To post-process results, the `FVSOut.db` SQLite files can be read with the
  salvaged Python helpers in `src/fvs_tools` (see the top-level docs).
