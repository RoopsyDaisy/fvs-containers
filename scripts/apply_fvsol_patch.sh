#!/usr/bin/env bash
# Apply the carried fvsOL source patches (patches/*.patch) to the fvs-interface
# tree. These fixes adapt the vendored fvsOL to current CRAN package behaviour
# (e.g. RSQLite temp-table writes); see patches/README.md for each patch's
# rationale, evidence, and upstream status.
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

# A submodule checkout carries a ".git" *file* pointing at the superproject's
# gitdir. When this tree is COPYed into a Docker build (or any context lacking
# that gitdir) the pointer dangles and `git apply` aborts with "not a git
# repository". git apply needs no repo to patch a plain tree, so drop a dangling
# pointer. A valid .git (e.g. the live dev submodule) resolves and is untouched.
if [ -f "$SUB/.git" ] && ! git -C "$SUB" rev-parse --git-dir >/dev/null 2>&1; then
  rm -f "$SUB/.git"
fi

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

# Completeness guard for fvsOL-rsqlite-temp-tables.patch: the schema-qualified
# dbWriteTable(con, DBI::SQL("temp.<name>"), ...) form throws "Named parameters
# not used in query" on RSQLite >= 3 (see patches/README.md). After patching, no
# such literal site may remain in fvsOL/R. (The dynamic DBI::SQL(<var>) site and
# the "temp.FVS_ClimAttrs" plain-string site are different cases, out of scope,
# and intentionally not matched.)
if [ -d "$SUB/fvsOL/R" ]; then
  if grep -rnE 'dbWriteTable\([^,]+,[[:space:]]*(name=)?DBI::SQL\("temp\.' "$SUB/fvsOL/R"; then
    echo "   ERROR: un-converted DBI::SQL(\"temp.X\") dbWriteTable site(s) remain (above)" >&2
    exit 1
  fi
fi
