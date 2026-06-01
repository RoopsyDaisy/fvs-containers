# Running FVS in parallel on Hellgate (Apptainer + SLURM)

Approach doc for batch command-line FVS runs on the University of Montana
**Hellgate** research cluster ([`hellgate.rci.umt.edu`](https://www.umt.edu/it/rci/hellgate/)).
Goal: build many keyword (`.key`) files (e.g. in R), then run them in parallel —
one FVS invocation per keyword file.

> Status: the batch **runner and pattern are implemented in [`cluster/`](../cluster/)
> and validated locally** (dev container, native engine). What's **not yet tested
> on the cluster** are the cluster-specific pieces (real `.sif` under
> Apptainer/FUSE, SLURM submission, partitions, fakeroot, BeeGFS bind paths) —
> derived from UM RCI docs and marked **[confirm on cluster]** below; verify
> once we have access.
>
> **First-contact runbook:** the very first cluster session, run
> [`cluster/hellgate_probe.sh`](../cluster/hellgate_probe.sh). It probes
> partitions, walltime caps, Apptainer + fakeroot, the storage layout, and
> login-node registry egress in one shot, then submits one tiny smoke job to
> prove the path end-to-end. Output is a single markdown report you can paste
> back here to calibrate `cluster/fvs_array.sbatch` defaults.

> **Prior art search (2026-05-30): none.** No other public FVS-on-HPC effort
> turned up in a focused scout (GitHub code/repo search, web search) — closest
> is Vibrant Planet's `usfs-fvs` GHCR image, which we consume but doesn't
> address the SLURM-array side.

## TL;DR

1. Produce one Apptainer image (`.sif`) containing the FVS CLI engine for your
   variant (e.g. `ie`). Put it on BeeGFS (`/mnt/beegfs/...`).
2. Submit a **SLURM job array** — one array task per `.key` file. Each task runs
   `apptainer exec fvs.sif FVSie --keywordfile=stand.key` in its own output
   directory.
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

Important and easy to trip on: **invoke FVS with the `--keywordfile=` flag, not
by piping the filename on stdin.** Run with no input and it prompts:

```
ENTER KEYWORD FILE NAME (15):
```

You *can* answer that prompt over stdin (`echo mystand.key | FVSie`), but that
only works for fully *database-self-contained* keyword files. For *flat-file*
keyword files (a `.key` with a separate `.tre`) FVS drops into interactive
per-filename prompting and the run fails. So the robust invocation — used by the
batch runner (`cluster/fvs_run_one.sh`) for **both** styles — is:

```bash
FVSie --keywordfile=mystand.key   # NOT  echo mystand.key | FVSie
```

With `--keywordfile=`, FVS derives the auxiliary filenames (`.tre`/`.out`/`.trl`)
from the keyword base name and runs non-interactively.

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

## The batch runner (implemented in `cluster/`)

The concrete scripts live in [`cluster/`](../cluster/) and are **manifest-driven**
— one keyword-file path per line; SLURM array task *N* runs line *N*:

- [`cluster/build_sif.sh`](../cluster/build_sif.sh) — convert the FVS OCI image to a `.sif`.
- [`cluster/fvs_array.sbatch`](../cluster/fvs_array.sbatch) — the SLURM array job.
- [`cluster/fvs_run_one.sh`](../cluster/fvs_run_one.sh) — the per-task unit: make an isolated run dir, stage shared inputs, run `FVS<variant> --keywordfile=<key>` (`apptainer exec` if `SIF` is set, else the native binary).
- [`cluster/run_local.sh`](../cluster/run_local.sh) — run the same batch with **no scheduler/container** against a native binary (testing / non-HPC machines).

Full how-to in [`cluster/README.md`](../cluster/README.md). The essentials:

```bash
ls inputs/*.key > keyfiles.txt          # manifest
sbatch --array=1-$(wc -l < keyfiles.txt)%50 \
  --export=SIF=$PWD/fvs_ie.sif,VARIANT=ie,MANIFEST=$PWD/keyfiles.txt,FVS_INPUT=$PWD/inputs/FVS_Data.db \
  cluster/fvs_array.sbatch
```

- Each task runs in its own `runs/<keyfile>/` dir, so reused output names (e.g. `FVSOut.db`) never collide.
- `FVS_INPUT` stages a **shared inventory DB** (read by the keyword files' relative `DSNin`) into each run dir — the typical "batch built in R" pattern. Omit if the keyword files are self-contained.
- `%50` caps concurrency; add `--account`/`--partition` per Hellgate policy.
- The same `fvs_run_one.sh` runs on the cluster and locally, so only the engine wrapper (`apptainer exec` vs native) differs.

**Validated locally** (dev container, native engine, via `run_local.sh`): a batch
of keyword files each produced its own isolated `runs/<name>/` with a populated
output DB and no collisions, and per-task failures are reported (non-zero exit).
What remains **Hellgate-only**: `apptainer exec` of a real `.sif` (needs FUSE),
real SLURM submission, and the specifics below.

## Collecting outputs

Each task leaves a self-contained `runs/<stand>/` directory. Keep **per-run
output DBs** (the default — each run writes into its own dir) and merge them in a
final step; don't point all runs at one shared output DB, since FVS appends and
concurrent writers to one SQLite file contend.

## Open questions to confirm with cluster access (next week)

The first-session script [`cluster/hellgate_probe.sh`](../cluster/hellgate_probe.sh)
answers these mechanically; the list below is what we expect its report to
populate.

- **Partitions & limits** — names, default/max walltime, cores/mem per node,
  array-size and concurrent-task caps (`sinfo`, `scontrol show config`).
- **Network egress** — can the login node reach `ghcr.io` / Docker Hub? If yes,
  `apptainer pull docker://...` is in play; if no, build off-cluster + `scp`.
- **fakeroot** — `/etc/subuid` entry present for the account? (UM RCI docs
  describe fakeroot as "available", but per-account.)
- **Modules** — is `apptainer` on `PATH` by default or behind `module load`?
  Is R available for keyword generation directly on the cluster?
- **Storage** — actual BeeGFS mount paths and per-area quotas (per UM RCI's
  Hellgate storage page and the Goodlab user notes the user-facing layer is
  BeeGFS, ~800 TB). Whether to publish the SIF to a shared `Containers`
  area for other users.
- **Account / QOS** — `sacctmgr` association for our account; the sbatch
  template will need `--account=<name>`.
- **FVS CLI path in the image** — confirm `FVS<variant>` is on `PATH` (and the
  exact return-code behaviour) inside the pulled `.sif`.

## References

- UM RCI — Apptainer: https://www.umt.edu/it/rci/getting-started/apptainer/
- UM RCI — SLURM: https://www.umt.edu/it/rci/getting-started/slurm/
- fvs-build: https://github.com/Vibrant-Planet-Open-Science/fvs-build
- microfvs (REST API + KCP treatment library): https://github.com/Vibrant-Planet-Open-Science/microfvs
