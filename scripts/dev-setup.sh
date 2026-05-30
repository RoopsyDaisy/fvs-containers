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
  # Don't bail on `update` errors: third-party PPAs in the base image (e.g.
  # deadsnakes, ondrej/php) live on ppa.launchpadcontent.net, which isn't on the
  # Trusted network-access allowlist and 403s -- making apt exit non-zero even
  # though the main Ubuntu archive (which is on the allowlist) refreshed fine.
  # `install` runs from the cached lists either way; let it speak for itself.
  $SUDO apt-get update -qq 2>/dev/null \
    || log "apt update reported errors (likely blocked PPA); continuing to install"
  $SUDO apt-get install -y --no-install-recommends "$@" 2>/dev/null \
    || log "apt install failed (non-fatal): $*"
}

# Install the shell linter (lints the repo's *.sh; the advisory CI job uses it).
if have shellcheck; then log "shellcheck present"; else
  log "installing shellcheck"; apt_install shellcheck
fi

# R + lintr — lets the agent run the R lint checks and parse-check *.R locally.
if have Rscript; then log "R present"; else
  log "installing r-base-core"; apt_install r-base-core
fi
if have Rscript && ! R_PROFILE_USER=/dev/null Rscript --vanilla \
    -e 'q(status = !requireNamespace("lintr", quietly = TRUE))' >/dev/null 2>&1; then
  # lintr pulls xml2/openssl/curl, whose source builds need libxml2-dev,
  # libssl-dev, libcurl4-openssl-dev system headers (CRAN ships source on Linux).
  log "installing lintr system deps (libxml2-dev libssl-dev libcurl4-openssl-dev)"
  apt_install libxml2-dev libssl-dev libcurl4-openssl-dev
  log "installing lintr R package"
  # --vanilla + R_PROFILE_USER=/dev/null bypasses the project's renv autoload,
  # which would otherwise route through packagemanager.posit.co (not allowlisted)
  # and ignore the `repos=` we pass. cloud.r-project.org IS allowlisted.
  R_PROFILE_USER=/dev/null Rscript --vanilla \
      -e 'install.packages("lintr", repos="https://cloud.r-project.org")' >/dev/null 2>&1 \
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
log "  SKIP=hadolint-docker pre-commit run --all-files     # blocking gate (actionlint + gitleaks)"
log "  shellcheck scripts/*.sh cluster/*.sh"
log "  Rscript -e 'lintr::lint_dir(\"scripts\")'"
log "NOTE: Docker image builds + in-image tests remain CI-only (no runtime here)."
log "NOTE: hadolint-docker is skipped above because pre-commit's hook needs a"
log "      Docker daemon; CI runs it. Dockerfile changes still lint in CI."
