#!/usr/bin/env bash
# Optional dev/CI-session bootstrap: preinstall the fast lint + R toolchain so
# lint/parse errors are caught locally instead of in a CI round. See
# docs/ENVIRONMENT_SETUP.md.
#
# Designed to be SAFE to run anywhere: it skips tools already present, never
# fails the session if a download is blocked (best-effort), and does NOT touch
# Docker/R-package-restore (image builds are CI-only by design). Idempotent.
#
# Wire it into the Claude Code environment's startup hook, or run by hand:
#   bash scripts/dev-setup.sh
set -uo pipefail   # NOT -e: a blocked install must not abort the session

log() { printf '>>> dev-setup: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Use sudo only if present and not already root.
SUDO=""
if [ "$(id -u)" -ne 0 ]; then have sudo && SUDO="sudo"; fi

apt_install() {
  have apt-get || { log "no apt-get; skipping: $*"; return 0; }
  $SUDO apt-get update -qq 2>/dev/null || { log "apt update blocked; skipping: $*"; return 0; }
  $SUDO apt-get install -y --no-install-recommends "$@" 2>/dev/null \
    || log "apt install blocked/failed (non-fatal): $*"
}

# Install the shell linter (lints the repo's *.sh; the advisory CI job uses it).
if have shellcheck; then log "shellcheck present"; else
  log "installing shellcheck"; apt_install shellcheck
fi

# R + lintr — lets the agent run the R lint checks and parse-check *.R locally.
if have Rscript; then log "R present"; else
  log "installing r-base-core"; apt_install r-base-core
fi
if have Rscript && ! Rscript -e 'requireNamespace("lintr")' >/dev/null 2>&1; then
  log "installing lintr R package"
  Rscript -e 'install.packages("lintr", repos="https://cloud.r-project.org")' >/dev/null 2>&1 \
    || log "lintr install blocked (non-fatal)"
fi

# pre-commit — runs the actual blocking gate (actionlint, hadolint, gitleaks)
# locally, so `pre-commit run --all-files` mirrors CI before pushing.
if have pre-commit; then log "pre-commit present"; else
  if have pipx; then pipx install pre-commit >/dev/null 2>&1 || log "pipx pre-commit blocked"
  elif have pip3;  then pip3 install --user pre-commit >/dev/null 2>&1 || log "pip pre-commit blocked"
  else log "no pipx/pip; install pre-commit manually if wanted"
  fi
fi

log "done. Local checks available (best-effort):"
log "  pre-commit run --all-files     # blocking gate (actionlint/hadolint/gitleaks)"
log "  shellcheck scripts/*.sh cluster/*.sh"
log "  Rscript -e 'lintr::lint_dir(\"scripts\")'"
log "NOTE: Docker image builds + in-image tests remain CI-only (no runtime here)."
