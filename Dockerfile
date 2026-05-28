# Devcontainer image for developing the FVS container/WebGUI tooling.
#
# This is the DEV environment, not a deliverable. The shippable images are
# docker/Dockerfile.fvs (slim engine) and docker/Dockerfile.webgui (FVS + WebGUI).
#
# Built on rocker/r2u (Ubuntu noble) so CRAN packages install as apt binaries with
# automatic system-dependency resolution, and so FVS compiles against the same
# toolchain/glibc as the WebGUI deliverable. FVS itself is NOT built here; it is
# compiled from the mounted, pinned submodule by .devcontainer/postCreate.sh after
# the container is created.

FROM docker.io/rocker/r2u:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# Toolchain + FVS runtime libs, dev conveniences and Python (for the salvaged
# batch tools). The fvsOL R package set is NOT installed here; it is restored
# from renv.lock (pinned P3M snapshot) by postCreate. We install the *system*
# libraries those R packages need at runtime (derived via pak::pkg_sysreqs for
# ubuntu-24.04), since renv installs R binaries but not their apt dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
        # build + run FVS (meson + ninja drive the fvs-build overlay)
        gfortran gcc g++ make meson ninja-build git ca-certificates \
        libgfortran5 libquadmath0 libstdc++6 \
        # dev conveniences
        sudo curl rsync openssh-client less nano \
        python3 python3-venv python3-pip \
        # native deps for the renv-managed fvsOL R package set
        libcairo2-dev libfreetype6-dev libpng-dev libxml2-dev libssl-dev \
        libgl1-mesa-dev libglu1-mesa-dev libicu-dev libuv1-dev zlib1g-dev \
        libsqlite3-dev libgdal-dev gdal-bin libgeos-dev libproj-dev \
        libudunits2-dev libabsl-dev pandoc \
    && rm -rf /var/lib/apt/lists/*

# renv (not bspm/r2u) manages the R package set, pinned via renv.lock. Disable
# r2u's bspm hook so install.packages / the renv bootstrap resolve from the
# pinned P3M snapshot instead of apt, and pre-install renv for postCreate.
RUN sed -i 's/^suppressMessages(bspm::enable())/# bspm disabled: R packages are managed by renv (see renv.lock)/' /etc/R/Rprofile.site \
    && R -q -e 'install.packages("renv", repos="https://packagemanager.posit.co/cran/__linux__/noble/2026-05-15")'

# uv for the Python batch tooling
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv

# Unprivileged user (UID/GID are remapped by the devcontainer runtime).
ARG USERNAME=vscode
RUN useradd -m "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${USERNAME}
# Pre-create the Claude Code state dir so the named volume mounted here inherits
# vscode ownership (rootless volume copy-up), avoiding root-owned mount surprises.
RUN mkdir -p /home/${USERNAME}/.claude
WORKDIR /workspaces/fors591
CMD ["/bin/bash"]
