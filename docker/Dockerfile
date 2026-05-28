# Consolidated multi-target build for the FVS deliverables.
#
# One common base -- fvs-r-base = FVS engine + R + renv-pinned packages + rFVS --
# that BOTH deliverables derive from, so a keyword file or R workflow tested in
# one image runs identically in the other (and in the dev container, which shares
# the same rocker/r2u base, renv.lock and vendor/fvs source).
#
#   fvs-r-base
#     |-- webgui   FVS + fvsOL Shiny GUI (port 3838)          [interactive]
#     +-- cluster  FVS + R + rFVS (CLI batch + R workflows)   [HPC -> .sif]
#
# Build (context = repo root); works the same in CI or on a workstation/lab PC
# with podman (docker/podman are CLI-compatible -- see scripts/build_images.sh):
#   docker build -f docker/Dockerfile --target webgui  -t fvs-webgui:ie  --build-arg FVS_VARIANT=ie .
#   docker build -f docker/Dockerfile --target cluster -t fvs-engine:ie  --build-arg FVS_VARIANT=ie .
#
# FVS provenance (hybrid): FVS_BASE=source (default) compiles FVS from the pinned
# vendor/fvs + fvs-build overlay; FVS_BASE=ghcr bases off the prebuilt usfs-fvs
# image. Requires BuildKit (default in modern docker/podman) so the unused FVS
# provider stage is skipped.

ARG FVS_VARIANT=ie
ARG FVS_TAG=FS2026.1
ARG FVS_BASE=source

# --- FVS provider A: compile from vendored, pinned source (canonical) ---------
FROM docker.io/ubuntu:24.04 AS fvs-source
ARG FVS_VARIANT
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        gfortran gcc g++ meson ninja-build ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY vendor/fvs /src/fvs
COPY vendor/fvs-build /src/fvs-build
COPY scripts/build_fvs.sh /src/build_fvs.sh
RUN bash /src/build_fvs.sh /src/fvs "${FVS_VARIANT}" /opt/fvs/bin

# --- FVS provider B: prebuilt GHCR image (opt-in: --build-arg FVS_BASE=ghcr) ---
# NOTE: assumes the usfs-fvs image exposes FVS<variant> on PATH and ships the
# FVS<variant>.so embedder that rFVS loads. The exact in-image path could not be
# verified here (no container runtime); confirm against the published image and
# adjust the copy below if needed before relying on FVS_BASE=ghcr.
FROM ghcr.io/vibrant-planet-open-science/usfs-fvs:${FVS_TAG} AS fvs-ghcr
ARG FVS_VARIANT
RUN mkdir -p /opt/fvs/bin \
    && exe="$(command -v FVS${FVS_VARIANT})" \
    && cp "$exe" /opt/fvs/bin/ \
    && so="$(dirname "$exe")/FVS${FVS_VARIANT}.so" \
    && { [ -f "$so" ] && cp "$so" /opt/fvs/bin/ || true; }

# --- select the FVS provider via FVS_BASE ------------------------------------
FROM fvs-${FVS_BASE} AS fvs-bin

# --- common base: rocker/r2u + renv-pinned R packages + rFVS + the FVS engine -
FROM docker.io/rocker/r2u:24.04 AS fvs-r-base
ARG FVS_VARIANT
ENV DEBIAN_FRONTEND=noninteractive
# Headless rgl: null device (no X11); 3D renders via WebGL in the browser.
ENV RGL_USE_NULL=TRUE

# FVS runtime libs + native deps for the renv-managed R package set (derived via
# pak::pkg_sysreqs for ubuntu-24.04). R packages come from renv.lock (pinned P3M
# snapshot), not apt; disable r2u's bspm hook so renv resolves from P3M.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git \
        libgfortran5 libquadmath0 libstdc++6 \
        libcairo2-dev libfreetype6-dev libpng-dev libxml2-dev libssl-dev \
        libgl1-mesa-dev libglu1-mesa-dev libicu-dev libuv1-dev zlib1g-dev \
        libsqlite3-dev libgdal-dev gdal-bin libgeos-dev libproj-dev \
        libudunits2-dev libabsl-dev pandoc \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^suppressMessages(bspm::enable())/# bspm disabled: R packages managed by renv/' /etc/R/Rprofile.site

# Restore the pinned CRAN package set from renv.lock (P3M binaries). Install renv
# and restore in ONE layer: otherwise renv's self-update during restore tries to
# rename the previously-installed renv, which lives on a lower Docker layer, and
# overlayfs fails that same-dir rename with EXDEV ("invalid cross-device link").
COPY renv.lock /tmp/renv.lock
RUN R -q -e 'install.packages("renv", repos="https://packagemanager.posit.co/cran/__linux__/noble/2026-05-27"); renv::restore(lockfile="/tmp/renv.lock", library="/usr/local/lib/R/site-library", prompt=FALSE)'

# rFVS from the patched vendored interface source (ships without a NAMESPACE, so
# patch -> roxygenize -> install). fvsOL is added only in the webgui target;
# patches are applied here so the patched tree is shared with that target.
COPY vendor/fvs-interface /src/fvs-interface
COPY patches /src/patches
COPY scripts/apply_fvsol_patch.sh /src/apply_fvsol_patch.sh
RUN bash /src/apply_fvsol_patch.sh /src/fvs-interface /src/patches \
    && R -q -e "roxygen2::roxygenize('/src/fvs-interface/rFVS'); remotes::install_local('/src/fvs-interface/rFVS', upgrade='never', force=TRUE)"

# The FVS engine: the CLI binary + the FVS<variant>.so embedder that rFVS loads.
COPY --from=fvs-bin /opt/fvs/bin /opt/fvs/bin
ENV PATH=/opt/fvs/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/fvs/bin
ENV FVS_BIN=/opt/fvs/bin
ENV FVS_VARIANT=${FVS_VARIANT}

# --- cluster deliverable: FVS + R + rFVS (CLI batch + R workflows -> .sif) -----
# Carries R + rFVS so both the keyword-file generation (rFVS::fvsMakeKeyFile) and
# the rFVS interactive workflow can run on the cluster, not just the bare CLI.
FROM fvs-r-base AS cluster
# Baked so the smoke test runs with no bind mount (avoids podman SELinux/UID
# mount issues): `<engine> run --rm <image> Rscript /opt/fvs/smoke_test.R`.
COPY scripts/smoke_test.R /opt/fvs/smoke_test.R
RUN useradd -m fvs
USER fvs
WORKDIR /work
CMD ["/bin/bash"]

# --- webgui deliverable: + fvsOL Shiny GUI -----------------------------------
FROM fvs-r-base AS webgui
RUN R -q -e "roxygen2::roxygenize('/src/fvs-interface/fvsOL'); remotes::install_local('/src/fvs-interface/fvsOL', upgrade='never', force=TRUE)"
ENV PORT=3838
COPY docker/webgui-app.R /opt/fvs/webgui-app.R
# baked smoke test (run with no bind mount), as in the cluster target
COPY scripts/smoke_test.R /opt/fvs/smoke_test.R
RUN useradd -m fvs
USER fvs
WORKDIR /work
EXPOSE 3838
CMD ["R", "-q", "-e", "source('/opt/fvs/webgui-app.R')"]
