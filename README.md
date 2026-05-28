# FVS in a box

Reproducible builds of the **Forest Vegetation Simulator (FVS)** and the
**FVSOnline WebGUI**, packaged as containers for foresters and researchers.

This repo compiles FVS from pinned upstream source (no opaque prebuilt binaries)
and ships it three ways:

| You want to… | Use | Audience |
|---|---|---|
| Click through FVS in a browser | **WebGUI image** | foresters, students, on a laptop |
| Run keyword files from the command line | **slim engine image** | scripted / reproducible runs |
| Run thousands of simulations | **Apptainer + SLURM** | researchers on the Hellgate cluster |

FVS is built from the [`vendor/fvs`](vendor/fvs) submodule (pinned to a tagged
release) including the NVEL volume-library submodule. The build recipe and the two
undocumented Linux gotchas it handles are written up in [docs/BUILD.md](docs/BUILD.md).

> **Clone with submodules** (the FVS source nests one of its own):
> ```bash
> git clone --recurse-submodules <this-repo>
> # or in an existing checkout: git submodule update --init --recursive
> ```

## The WebGUI (foresters)

A familiar point-and-click FVSOnline interface, with no local R, FVS, or Fortran
install required.

```bash
podman build -f docker/Dockerfile.webgui -t fvs-webgui:ie --build-arg FVS_VARIANT=ie .
podman run --rm -p 3838:3838 -v "$PWD/myproject:/work" fvs-webgui:ie
# then open http://localhost:3838
```

On **macOS**, run the same image via Docker Desktop or OrbStack — the container's
port 3838 is forwarded to the Mac, so you just open the URL in your browser.

## The command line (scripted runs)

```bash
podman build -f docker/Dockerfile.fvs -t fvs:ie --build-arg FVS_VARIANT=ie .
echo mykeys.key | podman run -i --rm -v "$PWD:/work" fvs:ie FVSie
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
scripts/build_fvs.sh    compile one FVS variant from source
docker/Dockerfile.fvs   slim engine image
docker/Dockerfile.webgui  FVS + R/Shiny WebGUI image
cluster/                Apptainer .sif build + SLURM array template
docs/BUILD.md           how the build works (and the upstream gaps it fills)
src/fvs_tools/          Python helpers for keyword generation + reading FVSOut.db
```
