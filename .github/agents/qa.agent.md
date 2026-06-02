---
name: QA
description: Build tests and validation steps for new features.
target: vscode
handoffs:
  - label: Report Issues
    agent: Implementer
    prompt: Tests identified issues above; please address before merging.
    send: false
---
# QA playbook

> This is an **R + shell + Docker** repo (no Python/pytest/notebooks). Tests are
> base-R harnesses run in-image; the build gates on them.

- Extend the base-R harnesses (`tests/run_tests.R` engine integration,
  `scripts/smoke_test.R` regression guards) — no testthat, to keep `renv.lock`
  lean. Self-skip a guard where its dependency (e.g. fvsOL, the FVS binary) is absent.
- Run the gate the build runs: `bash scripts/build_images.sh` (builds + smoke +
  in-image `run_tests.R`); for a quick loop, `Rscript scripts/smoke_test.R`.
- Capture gaps as actionable TODOs if they cannot be fixed immediately.
