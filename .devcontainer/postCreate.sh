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
for pkg in rFVS fvsOL; do
  R -q -e "roxygen2::roxygenize('${BUILD_SRC}/${pkg}'); renv::install('${BUILD_SRC}/${pkg}')"
done

echo ">> Smoke test"
Rscript scripts/smoke_test.R

cat <<EOF

FVS is built in ${BIN_DIR} (variant ${VARIANT}).
  - Command line:  echo mykeys.key | LD_LIBRARY_PATH=${BIN_DIR} ${BIN_DIR}/FVS${VARIANT}
  - WebGUI:        bash scripts/run_webgui.sh   # then open the forwarded port 3838
EOF
