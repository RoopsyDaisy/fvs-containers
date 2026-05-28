# Running FVS in parallel on Hellgate (Apptainer + SLURM)

Approach doc for batch command-line FVS runs on the University of Montana
**Hellgate** research cluster. Goal: build many keyword (`.key`) files (e.g. in
R), then run them in parallel — one FVS invocation per keyword file.

> Status: **draft, not yet tested on Hellgate.** Everything below is derived
> from UM RCI online docs + the FVS engine's actual CLI behaviour. Items marked
> **[confirm on cluster]** need verification once we have Hellgate access.

## TL;DR

1. Produce one Apptainer image (`.sif`) containing the FVS CLI engine for your
   variant (e.g. `ie`). Put it on BeeGFS (`/mnt/beegfs/...`).
2. Submit a **SLURM job array** — one array task per `.key` file. Each task runs
   `echo stand.key | apptainer exec fvs.sif FVSie` in its own output directory.
3. Collect the per-run outputs (`.out`, `.trl`, `.sum`, and the FVS SQLite DB).

## Why this shape

- **Apptainer, not Docker** — Hellgate (like virtually all HPC) runs Apptainer
  (rootless, OCI-compatible). Docker's root daemon isn't available to users.
- **SLURM job array, not a service** — the workload is N independent, short
  FVS runs. A job array (`--array`) is the idiomatic fit: submit one script,
  SLURM fans it out across nodes and respects fairshare/limits. (This is why a
  REST service like `microfvs` is the wrong tool here, even though it's fine
  software — it's built for on-demand single-stand calls, not batch.)

## The FVS engine and how it takes input

Important and easy to trip on: **this FVS build reads the keyword *filename*
from standard input, not from a `--keywordfile` flag.** Running `FVSie` with no
input prints:

```
ENTER KEYWORD FILE NAME (15):
```

So the working invocation is:

```bash
echo mystand.key | FVSie       # NOT  FVSie --keywordfile=mystand.key
```

FVS resolves the keyword file relative to its **current working directory** and
writes its outputs (`.out`, `.trl`, `.sum`, and an output SQLite `.db` if the
keyword file requests `DATABASE`/`SQLOUT`) into that same directory. Two
consequences for batch runs:

- Give each run its **own working directory** so outputs don't collide.
- `--bind` that directory into the container and `cd` into it before running.

## The container

We are standardizing FVS provisioning on **fvs-build**
(`github.com/Vibrant-Planet-Open-Science/fvs-build`), which compiles the FVS
native binaries and publishes provenance-tracked runtime images to GHCR
(`ghcr.io/vibrant-planet-open-science/usfs-fvs`, e.g. tag `FS2026.1`). Our own
image (built from the same machinery as part of the `fvs-build` migration) will
contain `FVS<variant>` on `PATH`.

### Getting the `.sif` onto Hellgate

Three options, **most robust first**:

1. **Build the SIF off-cluster, copy it over** (recommended default). Build the
   OCI image where we control Docker (CI or the dev container), convert to SIF,
   and `scp` it to BeeGFS. The compute nodes then need *no* network at run time:
   ```bash
   # off-cluster (where Docker/podman is available):
   apptainer build fvs_ie.sif docker-daemon://fvs-cli:ie       # or docker-archive://fvs-cli-ie.tar
   scp fvs_ie.sif you@hellgate:/mnt/beegfs/projects/<you>/containers/
   ```
2. **Build on the login node from a registry** (if login-node egress is allowed
   **[confirm on cluster]**):
   ```bash
   apptainer build fvs_ie.sif docker://ghcr.io/vibrant-planet-open-science/usfs-fvs:FS2026.1
   ```
3. **Build on-cluster from a def file with `--fakeroot`** (UM docs say fakeroot
   is available). Use only if 1–2 don't fit.

There's also a shared container area at `/mnt/beegfs/projects/resources/Containers`
worth checking — an FVS image may already be there, or it may be a place to
publish ours for other users **[confirm on cluster]**.

## Running one stand (sanity check)

```bash
mkdir -p run01 && cp mystand.key run01/ && cd run01
echo mystand.key | apptainer exec --bind "$PWD" /mnt/beegfs/projects/<you>/containers/fvs_ie.sif FVSie
ls   # -> mystand.out, mystand.trl, mystand.sum, (mystand.db)
```

## Running many in parallel (SLURM job array)

Draft `fvs_array.sbatch` — **placeholders and resources need tuning [confirm on cluster]**:

```bash
#!/usr/bin/env bash
#SBATCH --job-name=fvs-batch
#SBATCH --array=0-999%50          # 0..N-1 tasks; %50 caps concurrency — set N and cap per partition limits
#SBATCH --cpus-per-task=1         # FVS CLI is single-threaded per run
#SBATCH --mem=2G                  # per task; tune to your stand sizes
#SBATCH --time=00:30:00           # per task walltime
#SBATCH --output=logs/fvs_%A_%a.out
#SBATCH --error=logs/fvs_%A_%a.err
# #SBATCH --partition=<TBD>       # set via `sinfo` on Hellgate

set -euo pipefail
SIF=/mnt/beegfs/projects/<you>/containers/fvs_ie.sif
RUNDIR=/mnt/beegfs/projects/<you>/fvs_runs        # holds the *.key files
VARIANT=ie

# Stable task -> keyword-file mapping (sorted), so re-runs are reproducible.
mapfile -t KEYS < <(cd "$RUNDIR" && ls -1 *.key | sort)
KEY="${KEYS[$SLURM_ARRAY_TASK_ID]:-}"
[ -n "$KEY" ] || { echo "no key for task $SLURM_ARRAY_TASK_ID"; exit 0; }

WORK="$RUNDIR/out/${KEY%.key}"
mkdir -p "$WORK"
cp "$RUNDIR/$KEY" "$WORK/"
cd "$WORK"
echo "$KEY" | apptainer exec --bind "$WORK" "$SIF" "FVS${VARIANT}"
```

Submit, sizing the array to the number of keyword files:

```bash
cd /mnt/beegfs/projects/<you>/fvs_runs
N=$(ls -1 *.key | wc -l)
mkdir -p logs out
sbatch --array=0-$((N-1))%50 fvs_array.sbatch
```

(Once this works we'll wrap it in a small `submit_fvs_batch.sh` so you just point
it at a directory of `.key` files.)

## Collecting outputs

Each task leaves a self-contained `out/<stand>/` directory. If keyword files
write to per-run SQLite DBs you can merge them afterward, or point all runs at
one shared DB only if you serialize writes (FVS appends — concurrent writers to
one SQLite file will contend). Simplest: per-run DBs, merged in a final step.

## Open questions to confirm with cluster access (next week)

- **Partitions & limits** — names, max walltime, cores/mem per node, array-size
  and concurrent-task caps (`sinfo`, cluster policy).
- **Network egress** — can the login node pull `docker://`/`ghcr.io`? Determines
  build-on-cluster vs build-and-transfer.
- **fakeroot** — enabled for the account? (docs say "available".)
- **Modules** — is `apptainer` on `PATH` by default, or `module load`? Is R
  available on Hellgate for generating the keyword files there?
- **BeeGFS** — project path, quotas, and whether to publish the SIF to the
  shared `/mnt/beegfs/projects/resources/Containers` area.
- **FVS CLI path in the image** — confirm `FVS<variant>` is on `PATH` (and the
  exact stdin/return-code behaviour) in our `fvs-build`-based image.

## References

- UM RCI — Apptainer: https://www.umt.edu/it/rci/getting-started/apptainer/
- UM RCI — SLURM: https://www.umt.edu/it/rci/getting-started/slurm/
- fvs-build: https://github.com/Vibrant-Planet-Open-Science/fvs-build
- microfvs (REST API + KCP treatment library): https://github.com/Vibrant-Planet-Open-Science/microfvs
