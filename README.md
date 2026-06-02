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
release) including the NVEL volume-library submodule, compiled by the Meson
[`fvs-build`](vendor/fvs-build) overlay. The build recipe — and how it wires the
engine up for the rFVS/fvsOL R layer — is written up in [docs/BUILD.md](docs/BUILD.md).

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
- **An R-enabled engine** — the engine image carries R + rFVS, so keyword
  generation and rFVS-driven runs work *on the cluster*, not just the bare CLI.
  The HPC batch runner and the R keyword-file workflows live in the companion
  repo **[fvs-hpc-toolkit](https://github.com/RoopsyDaisy/fvs-hpc-toolkit)**, which
  runs against the image this repo publishes.
- **A reproducible, patchable build** — rebuild the *same* engine + R stack from
  pinned source (or base off the prebuilt image via a build flag), rather than
  depending on an opaque artifact.

We add nothing to FVS itself — the value is entirely this usability, scale, and
reproducibility layer. If you only need to run one keyword file by hand, the
prebuilt image is enough; the moment you want the GUI, HPC batch, R-driven config,
or a reproducible build, that's the gap this repo fills.

## The WebGUI (foresters)

A familiar point-and-click FVSOnline interface in your browser — **no local R,
FVS, or Fortran install**. You only need a container runtime; the prebuilt image
is *pulled* from GitHub Container Registry, not built.

**Requirements (any OS):** a container runtime (Docker Desktop, OrbStack, or
Podman) + a few GB of free disk for the image. The commands use `docker`; if you
installed Podman, just replace `docker` with `podman`. The container works in
`/work`, so mount a host folder there to keep your projects/outputs.

### macOS
1. Install **[Docker Desktop](https://www.docker.com/products/docker-desktop/)** or
   **[OrbStack](https://orbstack.dev)**, and open it (the runtime must be running).
2. In **Terminal**:
   ```bash
   docker pull ghcr.io/roopsydaisy/fvs-containers-webgui:ie
   mkdir -p ~/fvs-projects
   docker run --rm -p 3838:3838 -v "$HOME/fvs-projects:/work" ghcr.io/roopsydaisy/fvs-containers-webgui:ie
   ```
3. Open **<http://localhost:3838>**. Stop it with **Ctrl-C** in Terminal.

### Windows
1. Install **[Docker Desktop](https://www.docker.com/products/docker-desktop/)**
   (accept the WSL 2 backend) and open it.
2. In **PowerShell**:
   ```powershell
   docker pull ghcr.io/roopsydaisy/fvs-containers-webgui:ie
   mkdir $HOME\fvs-projects -Force
   docker run --rm -p 3838:3838 -v "${HOME}\fvs-projects:/work" ghcr.io/roopsydaisy/fvs-containers-webgui:ie
   ```
3. Open **<http://localhost:3838>**. Stop it with **Ctrl-C**.

### Linux
1. Install **[Docker](https://docs.docker.com/engine/install/)** or Podman
   (`sudo apt install podman` / `sudo dnf install podman`).
2. ```bash
   docker pull ghcr.io/roopsydaisy/fvs-containers-webgui:ie
   mkdir -p ~/fvs-projects
   docker run --rm -p 3838:3838 -v "$HOME/fvs-projects:/work" ghcr.io/roopsydaisy/fvs-containers-webgui:ie
   ```
   On **SELinux** systems (Fedora/RHEL) add `:z` to the mount: `-v "$HOME/fvs-projects:/work:z"`.
3. Open **<http://localhost:3838>**.

> **Notes.** The first `pull` downloads a few GB and can take a few minutes; later
> runs are instant. If port 3838 is busy, map another: `-p 8080:3838`, then open
> `http://localhost:8080`. If `docker pull` fails with `unauthorized`/`denied`,
> the GHCR package isn't public yet — make `fvs-containers-webgui` public in the
> repo's **Packages** settings, or `docker login ghcr.io` with a GitHub token
> (`read:packages` scope). On **Apple Silicon Macs** (M1–M4) the plain commands
> above work as-is — Docker emulates the `amd64` image. You'll see a harmless
> `platform … does not match` warning; add `--platform linux/amd64` to silence it.
> The same applies to the engine image below.

<details><summary><b>Build it yourself (maintainers)</b></summary>

To build the image from source instead of pulling (e.g. for a new FVS variant):

```bash
podman build -f docker/Dockerfile --target webgui -t fvs-webgui:ie --build-arg FVS_VARIANT=ie .
podman run --rm -p 3838:3838 -v "$PWD/myproject:/work" fvs-webgui:ie
```
</details>

## The command line (scripted runs)

Pull the engine image and run a keyword file by hand (no build):

```bash
docker pull ghcr.io/roopsydaisy/fvs-containers-engine:ie
docker run --rm -v "$PWD:/work" -w /work ghcr.io/roopsydaisy/fvs-containers-engine:ie FVSie --keywordfile=mykeys.key
# FVS writes FVSOut.db and report files next to your keyword file
```

For many keyword files in parallel on HPC, use the cluster runner in
[fvs-hpc-toolkit](https://github.com/RoopsyDaisy/fvs-hpc-toolkit).

## The cluster (big simulation campaigns)

Pull the published engine image to an Apptainer `.sif` and fan runs out with a
SLURM array job — the runner, the R keyword generators, and the Hellgate runbook
are in **[fvs-hpc-toolkit](https://github.com/RoopsyDaisy/fvs-hpc-toolkit)**.

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
scripts/smoke_test.R    regression gate (R env + FVS engine + rFVS load)
tests/                  in-image FVS engine integration test; see tests/run_tests.R
docs/BUILD.md           how the build works (Meson fvs-build overlay + rFVS wiring)
docs/WORKFLOW.md        branch/PR/test-gate flow (and how to reuse it elsewhere)
```

## Testing & contributing

`tests/run_tests.R` runs pure-R unit tests (the `data/` input guard + the
keyword-file writer) and an engine integration test (runs FVS on the bundled
`iet01` `ie` example). It's baked into the images and invoked by
`scripts/build_images.sh`, so the same suite gates both CI and the GHCR publish.
The branch → PR → green-CI → merge flow is in [docs/WORKFLOW.md](docs/WORKFLOW.md).

## License

This repository's own code (Dockerfiles, build/cluster/R-workflow scripts) is
released under the [MIT License](LICENSE). The vendored upstreams it packages —
the USDA FVS engine and the rFVS/fvsOL R packages under `vendor/` — are works of
the U.S. Forest Service and carry their own (public-domain) terms; MIT covers
only this repo's wrapper layer, not the vendored source.
