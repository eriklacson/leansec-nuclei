# Plan — dockerfile-template-verification

Status: **approved 2026-07-03.** Architect decision: fail loudly only, skip retry logic (option 2a). Docker build layer caching (open question 2) left untracked as a separate follow-up, not bundled into this fix. Implementation proceeds per this plan.

## Proposed change

### 1. `docker/Dockerfile.local` — fail the build loudly on an empty template cache

Replace:
```dockerfile
# Bake Nuclei templates into the image so UPDATE_TEMPLATES=false works in tests
# and air-gapped environments without a runtime network call.
RUN nuclei -update-templates -silent
```

With:
```dockerfile
# Bake Nuclei templates into the image so UPDATE_TEMPLATES=false works in tests
# and air-gapped environments without a runtime network call. Verify templates
# actually landed — `-update-templates` can exit 0 on a failed/empty fetch
# (transient network issue, GitHub rate limit), silently shipping an image with
# zero templates. Path confirmed by direct verification against nuclei v3.4.10's
# .templates-config.json, not assumed.
RUN nuclei -update-templates -silent && \
    count=$(find "${HOME}/nuclei-templates" -name '*.yaml' | wc -l) && \
    if [ "${count}" -lt 1000 ]; then \
      echo "ERROR: only ${count} Nuclei templates found after update (expected 1000+); template fetch likely failed" >&2; \
      exit 1; \
    fi
```

Notes on this design:
- Checks `${HOME}/nuclei-templates` — the real path, confirmed live against the pinned
  `NUCLEI_VERSION=v3.4.10` (see scope.md §2), not `~/.config/nuclei/templates`.
- Threshold of 1000 rather than a strict `-gt 0`: a fetch that dies halfway could leave a
  handful of files rather than exactly zero — a low-but-nonzero count would still indicate
  a broken fetch. The real template set is ~13,400 files; 1000 is comfortably below normal
  variance across template releases but well above "fetch mostly failed."
- No `USER` directive changes needed — build and runtime both run as root, so `${HOME}`
  resolves identically at build time and run time (see scope.md §2).

### 2. `tests/test_container.py` — optional regression test

Add a test that builds with a deliberately broken template fetch (e.g. mock `nuclei` or
build-arg-gate the update command to a bad URL) and asserts `docker build` fails. **Flagged
as optional** — it adds meaningful build time to the test suite (a second image build) for a
build-tooling edge case. Recommend skipping unless the architect wants regression coverage
for this specific failure mode.

## Open questions (architect decision needed before IMPLEMENT)

1. **Retry logic around `-update-templates`?** A transient network blip or GitHub rate limit
   is exactly what caused the original failure. Failing loudly (this plan) turns a silent
   bad-image into a loud CI failure, but doesn't reduce how often CI flakes — it just makes
   the flake visible and re-runnable instead of shipping a broken image. Options:
   - **(a) Fail loudly only (this plan as written).** Simplest; relies on manual/automatic
     CI re-run when it flakes.
   - **(b) Add inline retry** (e.g. `for i in 1 2 3; do nuclei -update-templates -silent && break; sleep 5; done`)
     before the count check, so transient failures self-heal without a full CI re-run.
2. **Docker build layer caching in `ci.yaml`?** Separate from this bug fix — would reduce
   *how often* the network-dependent template fetch runs at all (cache hit → skip re-fetch),
   but is a bigger change to the CI workflow (e.g. `docker/build-push-action` + GHA cache,
   or `docker buildx` with `--cache-from`/`--cache-to`). Recommend tracking as a **separate
   follow-up task**, not bundled into this fix — this fix is a one-line-of-logic build
   correctness issue; caching is a CI performance/cost optimization with its own tradeoffs
   (cache invalidation on `NUCLEI_VERSION` bump, cache storage costs).
3. **Should the count check also run in any other Dockerfile with the same pattern?**
   **Resolved during READ, no additional file affected.** Only `docker/Dockerfile.local`
   calls `nuclei -update-templates`. `docker/Dockerfile` (no `.local` suffix) also exists but
   is a separate, apparently stale legacy file: it bases on `projectdiscovery/nuclei:latest`
   (no local template-update call — templates would come from upstream, not this repo's
   build), has an invalid `COPY ../scanner/profiles/` path (references outside its own build
   context, which Docker does not permit), and targets `/opt/nuclei/entrypoint.sh` —
   inconsistent with the current `/app`-rooted architecture in `docker/Dockerfile.local` and
   `docker/entrypoint.sh`. It isn't referenced by any command in `CLAUDE.md`. Flagged here for
   awareness; fixing or removing it is a separate decision, out of scope for this task.

## Verification (once approved and built)

- `docker build -f docker/Dockerfile.local -t leansecurity/leansec-nuclei:local .` succeeds
  and the count check passes under normal conditions.
- Manually verify the loud-failure path: temporarily point `-update-templates` at a bad state
  (e.g. `NUCLEI_TEMPLATES_DIR` override or a deliberately broken build-arg) and confirm
  `docker build` exits nonzero with the new error message, rather than succeeding silently.
- Re-run `poetry run python -m pytest -q --maxfail=1 --disable-warnings` (existing
  `tests/test_container.py` suite) to confirm no regression to the currently-passing tests.
- `poetry run black --check . && poetry run ruff check . && poetry run bandit -r . -x ".venv,venv,build,dist,docs,migrations,tests"` — this change is Dockerfile-only (no Python), expect no change in outcome.
- Grep the repo for any other Dockerfile with the same `-update-templates` pattern to confirm
  whether question 3 above applies to more than one file.

## Out of scope (per task file, unchanged)

- No production/cloud deployment changes.
- No CSFLite control mapping changes.
- Not related to or blocking already-merged PR #17.
- Docker build layer caching in CI (tracked as a possible separate follow-up per open
  question 2, not built here).
