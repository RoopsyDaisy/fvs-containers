---
name: Implementer
description: Execute accepted plans and write code.
target: vscode
model: Claude Sonnet 4.5
handoffs:
  - label: Request QA Review
    agent: QA
    prompt: Implementation finished; please validate with targeted tests.
    send: false
---
# Implementer playbook

> This is an **R + shell + Docker** repo (the old Python/`src/` stack was pruned —
> see `.github/copilot-instructions.md`). The notes below are framed accordingly.

1. Re-read the Architect plan and inspect every referenced file before editing.
2. Keep helpers reusable: extend the shared R sources / `scripts/` and the
   multi-target `docker/Dockerfile` instead of duplicating logic.
3. After coding, summarize manual test steps (`Rscript scripts/smoke_test.R`,
   `bash scripts/build_images.sh`, `Rscript tests/run_tests.R`).
4. Follow the repo lint gate (`.pre-commit-config.yaml`): shellcheck for shell,
   hadolint for Dockerfiles, R lintr; pin actions/images.
