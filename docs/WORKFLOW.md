# Development workflow

A deliberately lightweight flow for a small team (one human reviewer, plus a
local-PC and a cloud coding agent). The point is two checkpoints that pay for
themselves even solo — **a diff you read before it lands, and a test gate in
front of the GHCR publish** — without ceremony that only makes sense for a big
team. Designed to be copied to sibling repos (see *Exporting* below).

## The loop

1. **Branch.** Work on a feature branch (`feature/...`, or the agent's
   `claude/...` branch). Never commit straight to `main`.
2. **Commit** in small, described steps.
3. **Open a PR into `main`.** This is the review surface — one place to read code
   **and** docs together before they become real. Self-merge is fine; the PR is a
   *checkpoint*, not an approval queue.
4. **CI must be green** (`ci.yaml` — builds the images from source and runs the
   in-image smoke test + R test suite). Merge only on green.
5. **Merge to `main`.** `publish.yaml` rebuilds, re-runs the same tests, and only
   then pushes `:ie`/`:latest` to GHCR. A test failure stops the publish.

### What we deliberately skip (overhead at this scale)
Required-reviewer counts, CODEOWNERS, PR templates beyond the short checklist,
conventional-commit enforcement, changelog automation, multi-stage approvals.

## The test gate

`scripts/build_images.sh` runs, in each built image:
- `scripts/smoke_test.R` — R env + FVS engine + `rFVS` `.so` load (+ fvsOL drift
  guards on the WebGUI image).
- `tests/run_tests.R` — pure-R unit tests (the `data/` input guard + the
  keyword-file writer) and an engine integration test that runs FVS on the
  upstream `iet01` `ie` example (the `--keywordfile=` path the cluster batch uses).

Because **both** `ci.yaml` and `publish.yaml` call `build_images.sh`, the same
gate runs before a merge **and** before a publish — "CI green" == "builds + tests
pass on the workstation". Run the suite yourself anytime:

```bash
Rscript tests/run_tests.R                              # unit only on a plain R host
ENGINE=podman scripts/build_images.sh                  # full build + smoke + tests
```

Adding a test: drop an `*.R` file in `tests/unit/` (no engine) or
`tests/integration/` (may use the engine; self-skip when it's absent). Each file
calls `check("name", <expr-that-should-be-TRUE>)`; the harness collects results
and exits non-zero on any failure. Plain base-R, no `testthat` dependency.

## One-time GitHub setting (manual)

CI already gates PRs, but `main` should be protected so the gate can't be
bypassed (and because `main` auto-publishes). In **Settings → Branches → Add
branch ruleset** for `main`:
- Require a pull request before merging.
- Require status checks to pass → select **CI / Build images + in-image smoke
  test**.
- (Optional) Require branches to be up to date before merging.

This can't be set through the GitHub tools available to the cloud agent, so it's
a one-time human toggle per repo.

## Exporting this workflow to another repo

Portable, repo-encoded pieces (copy these):
- `.github/workflows/ci.yaml` + `publish.yaml` (the build-once-test-twice split).
- `.github/pull_request_template.md` (the short checklist).
- `tests/` harness pattern (`run_tests.R` + `unit/` + `integration/`).
- This doc.

Per-repo, not encoded in files: the branch-protection ruleset above (toggle it),
and the registry/image names in `publish.yaml`.
</content>
