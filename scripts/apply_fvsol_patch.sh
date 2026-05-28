#!/usr/bin/env bash
# Apply the carried fvsOL source patches (patches/*.patch) to the fvs-interface
# tree. These fixes adapt the vendored fvsOL to current CRAN package behaviour
# (e.g. RSQLite temp-table writes); see the patch headers for details.
#
# Idempotent: safe to run whether or not the patches are already present. A
# bind-mounted dev workspace keeps them across rebuilds; a fresh checkout / CI /
# Docker build stage does not. Uses `git apply`, which works on a plain file
# tree too (no .git required), so it runs inside Docker build stages.
#
#   apply_fvsol_patch.sh [INTERFACE_DIR] [PATCH_DIR]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SUB="${1:-$ROOT/vendor/fvs-interface}"
PATCH_DIR="${2:-$ROOT/patches}"

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
  echo "   no patches in $PATCH_DIR"
  exit 0
fi

for p in "${patches[@]}"; do
  if git -C "$SUB" apply --reverse --check "$p" 2>/dev/null; then
    echo "   already applied: $(basename "$p")"
  else
    git -C "$SUB" apply "$p"
    echo "   applied:         $(basename "$p")"
  fi
done
