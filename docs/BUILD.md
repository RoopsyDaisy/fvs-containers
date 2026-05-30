# Building FVS and the FVS WebGUI from source

This document explains how this repository builds the Forest Vegetation Simulator
(FVS) and the FVSOnline WebGUI from source, in containers, for a non-technical
forestry audience and for cluster use.

It deliberately **references the upstream documentation where it exists** and
**fills in the gaps** — in particular two Linux build steps that are not documented
upstream but are required for a clean build.

## Upstream sources (vendored as pinned submodules)

| Path | Upstream | What it is |
|------|----------|-----------|
| `vendor/fvs` | [ForestVegetationSimulator](https://github.com/USDAForestService/ForestVegetationSimulator) | FVS Fortran/C engine + per-variant build system. Has a nested submodule, `volume/NVEL` ([VolumeLibrary](https://github.com/FMSC-Measurements/VolumeLibrary)). |
| `vendor/fvs-interface` | [ForestVegetationSimulator-Interface](https://github.com/USDAForestService/ForestVegetationSimulator-Interface) | The R packages `rFVS` (drives FVS as a shared library) and `fvsOL` (the R-Shiny "FVSOnline" WebGUI). |

Both are git submodules pinned to specific commits, so the source we read is
exactly the source we build. Because FVS nests the NVEL submodule, clone with:

```bash
git clone --recurse-submodules <this-repo>
# or, in an existing checkout:
git submodule update --init --recursive
```

## Upstream build documentation (and its gaps)

The upstream build docs are fragmented and Windows-centric:

- GitHub wiki — <https://github.com/USDAForestService/ForestVegetationSimulator/wiki>
  (pages: *Downloading Source Code*, *Build Process in Windows* (Make / Visual
  Studio), *Creating Custom Variants*, *FVS API*, *rFVS*, *FVSOnline*, *Structure*).
  No real Linux build page.
- Open-FVS SourceForge wiki (archival) —
  [BuildProcess_UnixAlike](https://sourceforge.net/p/open-fvs/wiki/BuildProcess_UnixAlike/)
  is the only place with the Linux recipe (`cmake -G"Unix Makefiles" .` then
  `make` in the variant dir).

Neither documents the two Linux build steps that historically tripped up a
hand-rolled CMake build (see the *Historical note* at the end). We no longer hit
them, because we delegate compilation to the **Meson `fvs-build` overlay**, which
handles both.

## The FVS engine build (per variant)

Encapsulated in [`scripts/build_fvs.sh`](../scripts/build_fvs.sh), a thin wrapper
over the [`vendor/fvs-build`](../vendor/fvs-build) Meson overlay
([Vibrant-Planet-Open-Science/fvs-build](https://github.com/Vibrant-Planet-Open-Science/fvs-build)).
For variant `ie` it:

1. **Preflight** — checks `bin/FVSie_sourceList.txt` and the NVEL include file
   (`volume/NVEL/wdbkwtdata.inc`) exist, and deletes stray `*.mod` files that
   otherwise corrupt the compile (*"Reading module … Unexpected EOF"*).
2. **Configure + compile** — `meson setup <build> vendor/fvs-build
   -Dfvs_source_dir=vendor/fvs -Dvariants=ie -Dprofile=reference` then
   `meson compile`. The overlay restricts the build to the requested variant(s),
   puts the NVEL `.inc` directory on the include path, and produces the embedder
   library named the way rFVS expects — i.e. it absorbs the two historical gaps.
3. **Collect** — copies the two artifacts rFVS/the CLI need into `<out_bin_dir>`:

| Artifact | Kind | Contents |
|----------|------|----------|
| `FVSie` | executable | command-line FVS (invoke with `--keywordfile=<name>`) |
| `FVSie.so` | shared lib | the self-contained embedder rFVS/PyFVS `dyn.load`s; contains the `Cfvs*` R-interface symbols (no `lib` prefix) |

## The WebGUI (rFVS / fvsOL) wiring

`rFVS::fvsLoad(bin=..., fvsProgram="FVSie")` calls `dyn.load("FVSie.so")` — it
expects a single loadable library named `<program>.so`, then calls API routines
such as `.C("CfvsSetCmdLine", PACKAGE="FVSie")`. The `fvs-build` overlay produces
exactly that self-contained `FVSie.so` (with the `Cfvs*` symbols and the engine's
dependencies linked in), so `build_fvs.sh` just copies it next to the CLI — no
symlink or manual library juggling required. `LD_LIBRARY_PATH` (or the bin dir on
`PATH`) covers any remaining runtime `.so` lookups; the `docker/Dockerfile`
targets set `LD_LIBRARY_PATH=/opt/fvs/bin`, and `smoke_test.R`'s `rFVS/fvsLoad`
guard verifies the embedder actually loads.

The R side is plain package installation: install `rFVS` then `fvsOL` from the
patched `vendor/fvs-interface` source (`roxygenize` → `remotes::install_local`).
`fvsOL`'s dependencies are listed in `vendor/fvs-interface/fvsOL/DESCRIPTION`
(shiny, Cairo, rhandsontable, ggplot2, RSQLite, plyr, dplyr, colourpicker, rgl,
leaflet, zip, openxlsx, shinyFiles) and pinned via `renv.lock`.

## Verified

The image build (FVS compiled from source via the overlay + the renv-pinned R
stack) was validated on podman/Fedora against FVS tag `FS2026.1` (commit
`58a9752`, variant `ie`), producing a working `FVSie` (revision RV:20260401) that
passes the in-image smoke test, including the `rFVS/fvsLoad` embedder guard.

## Historical note: the previous hand-rolled CMake build

Before adopting the `fvs-build` overlay, this repo compiled FVS directly with
CMake and had to work around two undocumented Linux gotchas. They're recorded
here because they explain *why* the overlay exists and may help anyone reading an
older FVS build:

- **GAP #1 — `wdbkwtdata.inc`.** `ie/vols.f` does `INCLUDE 'wdbkwtdata.inc'`,
  shipped in the NVEL submodule, but `bin/CMakeLists.txt` only added `.h`/`.F77`
  dirs to the include path — never `.inc` — so the compile failed at ~12% with
  *"Cannot open included file 'wdbkwtdata.inc'"*. The fix was copying the file
  into the configured build dir before `make`.
- **GAP #2 — the `FVSie.so` name.** The CMake build produced `libFVS_ie.so` (with
  the `Cfvs*` symbols actually in `libFVSsql.so`, a `NEEDED` dependency), but
  rFVS `dyn.load`s `FVSie.so`, so a `FVSie.so -> libFVS_ie.so` symlink was
  required and the dependency `.so`s had to be on `LD_LIBRARY_PATH`.

The Meson overlay restricts variants, fixes the include path, and emits a single
self-contained `FVSie.so` directly, so neither workaround is needed today.
