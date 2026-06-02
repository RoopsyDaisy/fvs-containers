---
name: DataExplorer
description: Add or adapt datasets and data pipelines.
target: vscode
handoffs:
  - label: Plan Follow-up Work
    agent: Architect
    prompt: Dataset support added; outline next steps.
    send: false
---
# DataExplorer playbook

> This is an **R + shell + Docker** repo (no Python/`src/` stack). Data here is
> FVS inventory (the `data/` CSVs → an FVS-native SQLite DB the engine reads).

- Review dataset requirements (paths, sources, licensing); see `data/README.md`.
- Keep paths configurable via environment variables (e.g. `FVS_DATA_DIR`).
- Implement loaders as R scripts that emit the documented FVS schema
  (`FVS_StandInit` / `FVS_TreeInit`); the inventory→DB workflow lives in the
  companion `fvs-hpc-toolkit` repo.
- Document verification steps (row counts, schema checks) for data health.
