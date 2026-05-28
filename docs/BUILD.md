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

**Neither documents the two steps below**, both of which are required on Linux.

## The FVS engine build (per variant)

Encapsulated in [`scripts/build_fvs.sh`](../scripts/build_fvs.sh). For variant `ie`:

1. **Restrict to one variant.** `bin/CMakeLists.txt` globs `FVS*_sourceList.txt`
   and configures all ~25 variants. We narrow the glob to `FVSie_sourceList.txt`.
2. **Configure:** `cmake -G "Unix Makefiles" .` in `bin/` generates
   `bin/FVSie_CmakeDir/` and configures it (no compilation yet).
3. **GAP #1 — copy `wdbkwtdata.inc`.** `ie/vols.f` does `INCLUDE 'wdbkwtdata.inc'`.
   That file ships in the NVEL submodule (`volume/NVEL/wdbkwtdata.inc`), but the
   CMake logic only adds `.h`/`.F77` directories to the include path — never `.inc`
   directories — so the compile fails at ~12% with *"Cannot open included file
   'wdbkwtdata.inc'"*. The build directory itself is on the include path, so the
   fix is to copy the file into `bin/FVSie_CmakeDir/` before `make`. (Tellingly,
   prebuilt FVS build directories ship with this file already copied in — the step
   is real, just undocumented.)
4. **Compile:** `make` in `bin/FVSie_CmakeDir/`.

This produces four artifacts:

| Artifact | Kind | Contents |
|----------|------|----------|
| `FVSie` | executable | command-line FVS (reads keyword filename on stdin) |
| `libFVS_ie.so` | shared lib | the Fortran engine; NEEDs the two below |
| `libFVSsql.so` | shared lib | SQLite I/O **and** the `Cfvs*` R-interface wrappers (`base/apisubsc.c`, built under `-DCMPgcc`) |
| `libFVSfofem.so` | shared lib | Fire & Fuels (FOFEM) C code |

## The WebGUI (rFVS / fvsOL) wiring

`rFVS::fvsLoad(bin=..., fvsProgram="FVSie")` calls `dyn.load("FVSie.so")` — i.e. it
expects a single loadable library named `<program>.so`, and then calls API routines
such as `.C("CfvsSetCmdLine", PACKAGE="FVSie")`.

- The CMake build does **not** produce a file named `FVSie.so`; it produces
  `libFVS_ie.so`.
- The `Cfvs*` symbols rFVS calls live in `libFVSsql.so`, **not** in `libFVS_ie.so`.

**GAP #2 — the `FVSie.so` symlink.** `libFVS_ie.so` declares `libFVSsql.so` and
`libFVSfofem.so` as `NEEDED` dependencies (confirmed with `readelf -d`). So loading
`libFVS_ie.so` pulls in the other two, and `dlsym` resolves the `Cfvs*` symbols
through the dependency chain. Therefore we expose the engine to rFVS as:

```
FVSie.so -> libFVS_ie.so   (symlink)
```

with `LD_LIBRARY_PATH` (or the bin dir) covering the dependency `.so` files.
`scripts/build_fvs.sh` creates this symlink automatically.

The R side is plain package installation (per the upstream `makefile`s, via
`devtools::install`): install `rFVS` then `fvsOL`; `fvsOL`'s dependencies are listed
in `vendor/fvs-interface/fvsOL/DESCRIPTION` (shiny, Cairo, rhandsontable, ggplot2,
RSQLite, plyr, dplyr, colourpicker, rgl, leaflet, zip, openxlsx, shinyFiles).

## Verified

The engine build above was verified on Ubuntu 24.04 / gfortran 13.3 / cmake 3.28
against FVS commit `58a9752` (variant `ie`), producing a working `FVSie`
(revision RV:20260401).
