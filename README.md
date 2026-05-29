# FVS in a box

Reproducible builds of the **Forest Vegetation Simulator (FVS)** and the
**FVSOnline WebGUI**, packaged as containers for foresters and researchers.

This repo compiles FVS from pinned upstream source (no opaque prebuilt binaries)
and ships it three ways:

| You want to… | Use | Audience |
|---|---|---|
| Click through FVS in a browser | **WebGUI image** | foresters, students, on a laptop |
| Run keyword files from the command line | **engine image** | scripted / reproducible runs |
| Run thousands of simulations | **Apptainer + SLURM** | researchers on the Hellgate cluster |

FVS is built from the [`vendor/fvs`](vendor/fvs) submodule (pinned to a tagged
release) including the NVEL volume-library submodule. The build recipe and the two
undocumented Linux gotchas it handles are written up in [docs/BUILD.md](docs/BUILD.md).

> **Clone with submodules** (the FVS source nests one of its own):
> ```bash
> git clone --recurse-submodules <this-repo>
> # or in an existing checkout: git submodule update --init --recursive
> ```

## What this adds over the prebuilt FVS image

A prebuilt FVS image (e.g. `ghcr.io/vibrant-planet-open-science/usfs-fvs`) gives
you the FVS **engine** — the variant binaries — and nothing else. It can run a
keyword file you hand it. This repo turns that engine into a usable toolchain:

- **A point-and-click WebGUI** — FVSOnline (`fvsOL`) + R/Shiny layered on the
  engine, with the full R dependency set pinned (`renv` + a dated snapshot) for
  reproducibility. The base image has none of this.
- **Run-at-scale on HPC** — an Apptainer + SLURM batch runner for many keyword
  files, plus an **R-enabled** engine image so keyword generation and rFVS-driven
  runs work *on the cluster*, not just the bare CLI.
- **R workflows** — generate keyword files from inventory data
  (`rFVS::fvsMakeKeyFile`) and drive FVS cycle-by-cycle from R (`fvsInteractRun`).
  See [scripts/r_workflow/](scripts/r_workflow/).
- **A reproducible, patchable build** — rebuild the *same* engine + R stack from
  pinned source (or base off the prebuilt image via a build flag), rather than
  depending on an opaque artifact.

We add nothing to FVS itself — the value is entirely this usability, scale, and
reproducibility layer. If you only need to run one keyword file by hand, the
prebuilt image is enough; the moment you want the GUI, HPC batch, R-driven config,
or a reproducible build, that's the gap this repo fills.

## The WebGUI (foresters)

A familiar point-and-click FVSOnline interface, with no local R, FVS, or Fortran
install required.

```bash
podman build -f docker/Dockerfile --target webgui -t fvs-webgui:ie --build-arg FVS_VARIANT=ie .
podman run --rm -p 3838:3838 -v "$PWD/myproject:/work" fvs-webgui:ie
# then open http://localhost:3838
```

On **macOS**, run the same image via Docker Desktop or OrbStack — the container's
port 3838 is forwarded to the Mac, so you just open the URL in your browser.

## The command line (scripted runs)

```bash
podman build -f docker/Dockerfile --target cluster -t fvs-engine:ie --build-arg FVS_VARIANT=ie .
podman run --rm -v "$PWD:/work" fvs-engine:ie FVSie --keywordfile=mykeys.key
# FVS writes FVSOut.db and report files next to your keyword file
```

## The cluster (big simulation campaigns)

Convert the engine image to an Apptainer `.sif` and fan runs out with a SLURM
array job. See [cluster/README.md](cluster/README.md).

## Developing this repo

Open it in VS Code and "Reopen in Container". The devcontainer builds on the same
base as the WebGUI image, compiles FVS from the submodule on create, installs the
rFVS/fvsOL packages, and forwards port 3838. Then:

```bash
bash scripts/run_webgui.sh      # serve the WebGUI on the forwarded port 3838
```

Build any variant locally without the container:

```bash
scripts/build_fvs.sh vendor/fvs ie /tmp/fvs-ie   # -> FVSie + shared libs
```

## Layout

```
vendor/fvs              FVS engine source (submodule, pinned; nests volume/NVEL)
vendor/fvs-interface    rFVS + fvsOL (WebGUI) source (submodule, pinned)
vendor/fvs-build        Meson build overlay for compiling FVS (submodule)
docker/Dockerfile       one multi-target build: fvs-r-base -> webgui, cluster
scripts/build_fvs.sh    compile one FVS variant from source
scripts/build_images.sh build + in-image smoke test (docker/podman)
scripts/r_workflow/      R workflows: keyword generation (batch) + rFVS interactive
scripts/smoke_test.R    regression gate (R env + FVS engine + rFVS load)
cluster/                Apptainer .sif build + SLURM array template
docs/BUILD.md           how the build works (and the upstream gaps it fills)
```
