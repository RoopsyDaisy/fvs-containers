#!/usr/bin/env bash
# Devcontainer post-create: restore the pinned R environment, patch + compile FVS
# from the pinned submodule, and install the rFVS/fvsOL interface packages from
# the mounted source. R packages come from renv.lock (P3M binaries), so this
# stays quick.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

VARIANT="${FVS_VARIANT:-ie}"
BIN_DIR="$PWD/.devcontainer/fvs-bin"

# Ensure the persisted Claude Code volume is owned by vscode (safety net in case
# the named volume predates the image change that pre-creates the dir).
sudo chown vscode:vscode "$HOME/.claude" 2>/dev/null || true

echo ">> Applying carried fvsOL source patches"
bash scripts/apply_fvsol_patch.sh

echo ">> Restoring pinned R packages from renv.lock (P3M binaries)"
R -q -e 'renv::restore(prompt = FALSE)'

echo ">> Building FVS variant '${VARIANT}' -> ${BIN_DIR}"
bash scripts/build_fvs.sh vendor/fvs "${VARIANT}" "${BIN_DIR}"

echo ">> Installing rFVS and fvsOL from patched vendored source into the renv library"
# roxygenize() writes NAMESPACE/man into the package dir, so work on a throwaway
# copy to keep the vendor/ submodule pristine. renv::install targets the
# user-owned project library (no sudo, no site-library).
BUILD_SRC="$(mktemp -d)"
trap 'rm -rf "$BUILD_SRC"' EXIT
cp -r vendor/fvs-interface/rFVS vendor/fvs-interface/fvsOL "$BUILD_SRC/"
# fvsOL's keyword-parameter catalog (data/prms.RData) and in-app help
# (data/fvsOnlineHelpRender.RData) are gitignored, makefile-generated data objects
# that roxygenize/install do NOT produce. Generate them into the copy before
# install or the GUI's keyword-component editor + help break at runtime
# (data(prms) "not found"); the smoke test's fvsOL/data-artifacts guard enforces it.
R -q -e "setwd('${BUILD_SRC}/fvsOL'); source('parms/mkpkeys.R'); source('inst/extdata/mkhelp.R')"
for pkg in rFVS fvsOL; do
  R -q -e "roxygen2::roxygenize('${BUILD_SRC}/${pkg}'); renv::install('${BUILD_SRC}/${pkg}')"
done

echo ">> Smoke test"
Rscript scripts/smoke_test.R

# Install the local lint gate (the same hooks lint.yaml runs in CI: actionlint,
# hadolint, gitleaks). This means `git commit` runs them automatically, so the
# class of bug that used to escape to CI (broken workflow YAML, stray secrets,
# Dockerfile lints) gets caught at commit time. UPSTREAM_REVIEW.md M4.
# Non-fatal: a one-off network blip should not block devcontainer startup --
# the dev can re-run `pre-commit install` later.
if command -v pre-commit >/dev/null 2>&1; then
  echo ">> Installing pre-commit hooks"
  pre-commit install --install-hooks || echo "   pre-commit install failed (non-fatal)"
else
  echo ">> Note: pre-commit not on PATH; skipping hook install."
  echo "   Install with: pipx install pre-commit && pre-commit install"
fi

cat <<EOF

FVS is built in ${BIN_DIR} (variant ${VARIANT}).
  - Command line:  LD_LIBRARY_PATH=${BIN_DIR} ${BIN_DIR}/FVS${VARIANT} --keywordfile=mykeys.key
  - WebGUI:        bash scripts/run_webgui.sh   # then open the forwarded port 3838
EOF
