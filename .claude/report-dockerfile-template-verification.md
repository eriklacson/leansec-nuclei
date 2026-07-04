# Report — dockerfile-template-verification

Source task: `.claude/tasks/dockerfile-template-verification.md`. Full trail: `.claude/scope.md`
(READ) → `.claude/plan.md` (PLAN, architect-approved 2026-07-03: fail loudly only, skip retry
logic) → this file (REPORT).

## What was built

### `docker/Dockerfile.local`
After `nuclei -update-templates -silent`, added a count check on `${HOME}/nuclei-templates/*.yaml`
that fails the build (`exit 1`) with an explicit error message if fewer than 1000 templates are
found. Previously, a failed or empty template fetch could exit 0 and ship an image with zero
templates, silently breaking the `UPDATE_TEMPLATES=false` offline-test path.

The path (`${HOME}/nuclei-templates`) was confirmed by direct verification, not assumed: ran
nuclei v3.4.10 (the version pinned in this Dockerfile) locally and inspected the resulting
`.templates-config.json`, which reported `nuclei-templates-directory` at that path — not
`~/.config/nuclei/templates` as the original task file guessed. 13,416 actual template files
were found there after a real update.

## Verification results

| Check | Result |
|---|---|
| `docker build -f docker/Dockerfile.local -t leansecurity/leansec-nuclei:local .` (normal path) | Pass — template count check completed in ~13s, no error, image built successfully |
| Loud-failure path (isolated test: fake `nuclei` binary + empty `nuclei-templates/` dir, same count-check logic) | Confirmed — `docker build` exits 1 with `ERROR: only 0 Nuclei templates found after update (expected 1000+); template fetch likely failed` |
| `poetry run python -m pytest -q --maxfail=1 --disable-warnings` | Pass — all tests green, no regression |
| `poetry run black --check .` | Pass — 11 files unchanged |
| `poetry run ruff check .` | Pass — no issues |
| `poetry run bandit -r . -x ".venv,venv,build,dist,docs,migrations,tests"` | Pass — 107 pre-existing low-severity `assert`-in-tests findings, all in `tests/`, no new findings |
| Scope check: other Dockerfiles with the same `-update-templates` pattern | None — only `docker/Dockerfile.local` uses it. `docker/Dockerfile` (no `.local` suffix) is a separate, apparently stale legacy file (invalid `COPY ../scanner/profiles/` path, inconsistent `/opt/nuclei` layout, unreferenced in CLAUDE.md) — flagged, not modified, out of scope for this task |

## Decisions taken (per architect approval)

- **Fail loudly only — no retry logic.** A transient network/rate-limit failure during
  `-update-templates` will now fail the build outright rather than being silently masked or
  auto-retried. Relies on manual/automatic CI re-run when this flakes.
- **Docker build layer caching in CI left untracked** — not bundled into this fix, per
  plan.md's recommendation to keep this a scoped build-correctness fix rather than a CI
  performance change.

## Flagged as unresolved / architect-verified only

- **CI flakiness is reduced, not eliminated.** This fix converts a silent bad-image into a
  loud, re-runnable CI failure — it does not prevent the underlying transient network/rate-limit
  condition from occurring. If flakes become frequent, revisit the retry-logic option
  (plan.md open question 1, option 2b) or the Docker build caching option (open question 2).
- **`docker/Dockerfile` (no `.local` suffix)** is a stale/inconsistent legacy file discovered
  during this task's READ step. Not touched — fixing or removing it is a separate decision for
  the architect.
- **No live CI run of this fix exists yet** — verification above is local (`docker build`,
  isolated failure-path test, full local test/lint suite). The real signal will be the next
  CI run once this is pushed.

## Control ID validation

This task changes CI/build tooling only — no scanner output, no JSONL, no new CSFLite control
mappings. `csflite/controls.json` was not touched; no control ID validation applies.
