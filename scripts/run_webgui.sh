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
echo "Serving FVS WebGUI on http://0.0.0.0:${PORT:-3838}  (FVS_BIN=$BIN_DIR)"
exec R -q -e "source('docker/webgui-app.R')"
