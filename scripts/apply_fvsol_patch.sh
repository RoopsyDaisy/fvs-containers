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

# Completeness guard for fvsOL-rsqlite-temp-tables.patch: passing a DBI::SQL()
# object as the dbWriteTable `name` throws "Named parameters not used in query"
# on RSQLite >= 3 (see patches/README.md) -- both the literal DBI::SQL("temp.X")
# form (11 sites) and the dynamic DBI::SQL(<var>) form (the XLSX-export site,
# server.R). The patch converts ALL of them, so after patching no DBI::SQL-as-name
# write may remain in fvsOL/R. (The plain-string "temp.FVS_ClimAttrs" site is a
# different case -- not DBI::SQL -- so it doesn't match; tracked separately.)
if [ -d "$SUB/fvsOL/R" ]; then
  if grep -rnE 'dbWriteTable\([^,]+,[[:space:]]*(name[[:space:]]*=[[:space:]]*)?DBI::SQL\(' "$SUB/fvsOL/R"; then
    echo "   ERROR: un-converted DBI::SQL(...) dbWriteTable name site(s) remain (above)" >&2
    exit 1
  fi
fi
