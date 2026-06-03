#!/usr/bin/env bash
# Launch the FVSOnline (fvsOL) WebGUI against a locally built FVS bin directory.
# Intended for the devcontainer dev loop: run this, then open the forwarded
# port 3838 in a browser.
#
# Usage: scripts/run_webgui.sh [fvs_bin_dir]   (default: .devcontainer/fvs-bin)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BIN_DIR="${1:-$PWD/.devcontainer/fvs-bin}"
[ -d "$BIN_DIR" ] || { echo "FVS bin dir not found: $BIN_DIR (run .devcontainer/postCreate.sh first)" >&2; exit 1; }

export FVS_BIN="$BIN_DIR"
export LD_LIBRARY_PATH="$BIN_DIR:${LD_LIBRARY_PATH:-}"
# Master dir for fvsOL projects. In the image this is /work (the bind mount);
# for the dev loop keep projects out of the repo root by defaulting to the
# gitignored outputs/ tree.
export FVS_WORK="${FVS_WORK:-$PWD/outputs/webgui-projects}"
mkdir -p "$FVS_WORK"
echo "Serving FVS WebGUI on http://0.0.0.0:${PORT:-3838}  (FVS_BIN=$BIN_DIR, projects in $FVS_WORK)"
exec R -q -e "source('docker/webgui-app.R')"
