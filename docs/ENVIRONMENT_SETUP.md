# Environment & integration setup (Claude Code on the web)

How to make the cloud Claude Code sessions on this repo smoother. None of this
is required — the repo works without it — but each item removes a specific
friction we hit while building the CI/test stack. **All of these are settings on
your GitHub account or the Claude Code environment; the agent cannot set them
from inside the sandbox.**

Background docs: <https://code.claude.com/docs/en/claude-code-on-the-web>

---

## 1. Read-only GitHub token — so the agent can read CI logs

**Problem it solves:** the GitHub MCP integration exposes check *status*
(pass/fail) but not log *contents*, and the unauthenticated GitHub API gets
rate-limited. So when CI fails, the agent can see *that* it failed but not *why*
— it has to ask you to paste the failing log. A read-only token lets it fetch
raw job logs directly.

### Create the token
GitHub → **Settings → Developer settings → Personal access tokens →
Fine-grained tokens → Generate new token**
- **Resource owner:** RoopsyDaisy
- **Repository access:** Only select repositories → `fvs-containers`
- **Repository permissions** (all *Read-only*):
  - **Actions** (read) — workflow runs + logs
  - **Contents** (read) — code
  - **Pull requests** (read) — PR metadata
  - **Metadata** (read, auto-selected)
  - *(nothing else — no write, no admin)*
- **Expiration:** 90 days is reasonable.

### Make it available to the session
Add it as an environment variable named `GH_TOKEN` (or `GITHUB_TOKEN`):
- **Web sessions:** the environment's **Secrets / environment variables**
  config → add `GH_TOKEN=github_pat_…`, then start a fresh session.
- **Local Claude Code:** `export GH_TOKEN=github_pat_…` before launching.

> Scope note: this is **read-only on one repo**. It deliberately does NOT grant
> merge or branch-protection ability — those stay manual (the human gate is the
> point). If you ever *did* want the agent to merge/administer, that needs
> `Pull requests: write` + `Administration: write`, which we recommend against.

---

## 2. Setup script — so the agent can run linters / R locally

**Problem it solves:** the sandbox's network policy blocks `apt`, and there's no
R or pre-commit preinstalled, so the agent can't run shellcheck / R lint / the
pre-commit hooks *before* pushing — it finds out via a 3-minute CI round
instead. Twice this let a trivial bug (a stray-tag YAML break, an R parse error)
reach CI. A startup script that preinstalls the lint/R toolchain closes that gap.

### What to add
In the environment config, set a **setup script** (runs at container start)
that installs the cheap, fast tools — see the companion
[`scripts/dev-setup.sh`](../scripts/dev-setup.sh) in this repo, which is written
to be a safe no-op when the tools are already present or the network blocks the
install. Point the environment's startup hook at it, or inline the equivalent.

It installs: `shellcheck`, `r-base-core` + the `lintr` R package, and
`pre-commit` (+ `actionlint`/`hadolint` via the hooks). With these present the
agent can run `pre-commit run --all-files` and `Rscript` checks locally and
catch lint/parse errors before they reach CI.

### The hard limit (can't be fixed by config)
**Docker image builds still won't run in the sandbox** — there's no container
runtime (no Docker-in-Docker). So even with a perfect setup script, the image
build, the in-image smoke/integration tests, and the A4 buildx cache remain
**CI-only**. The setup script buys local *lint + R-unit* verification, not local
*image* verification. That part is inherent to this environment type.

### Network policy (alternative / complement)
If instead of a setup script you loosen the environment's **network policy** to
allow package installs, the agent can install tools on demand per session. A
setup script is cleaner (preinstalled, repeatable, lets you keep the policy
tight otherwise), but either works for the lint/R toolchain.

---

## Summary

| Want | Action (yours) | Removes |
|------|----------------|---------|
| Agent reads CI logs itself | Add read-only `GH_TOKEN` (§1) | the "paste the failing log" loop |
| Agent runs lint/R locally | Setup script `scripts/dev-setup.sh` (§2) | lint/parse bugs reaching CI |
| Agent builds/tests images locally | *not possible here* | — (stays CI-only) |
| Agent merges / sets branch protection | *not recommended* | — (keep the human gate) |
