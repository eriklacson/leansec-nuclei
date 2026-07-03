# Task: Verify Nuclei templates are actually baked in at Docker build time

## Problem

`docker/Dockerfile.local:25-27` bakes Nuclei templates into the image at build time
specifically so `UPDATE_TEMPLATES=false` works offline in CI/tests and air-gapped
environments:

```dockerfile
# Bake Nuclei templates into the image so UPDATE_TEMPLATES=false works in tests
# and air-gapped environments without a runtime network call.
RUN nuclei -update-templates -silent
```

Observed on the post-merge `main` CI run after PR #17
(`gh run view 28644556374`, job `lint-and-test`, step `Run tests`):

```
[FTL] Could not run nuclei: no templates provided for scan
```

Every scan profile failed and `tests/test_container.py::test_local_mode_produces_canonical_jsonl_and_normalized_json`
failed because no `.jsonl` files were produced.

## Root cause

- CI has no Docker layer caching (`.github/workflows/ci.yaml` — hosted runners are
  fresh VMs each run), so `RUN nuclei -update-templates -silent` re-fetches templates
  from the network on every single build.
- `-silent` appears to let the build step succeed (exit 0) even when the template
  fetch itself fails or returns nothing — there's no verification that templates
  actually landed. A transient network blip or GitHub rate limit produces a "valid"
  image with zero templates, silently breaking the invariant the comment on line
  25-26 promises.
- This is why PR #17's own branch check passed (`docker build` ~3 min earlier,
  templates fetched fine) while the merge-to-`main` run's independent fresh build
  failed minutes later — pure flake, unrelated to PR #17's actual (docs/Terraform-only)
  content.

## Proposed fix (needs architect approval before implementation — per CLAUDE.md execution loop)

1. After `nuclei -update-templates -silent` in `docker/Dockerfile.local`, add a
   verification step that fails the build loudly if the template count is zero, e.g.:
   ```dockerfile
   RUN nuclei -update-templates -silent && \
       test -n "$(find /root/.config/nuclei/templates -name '*.yaml' -print -quit)" || \
       (echo "ERROR: no Nuclei templates found after update" >&2 && exit 1)
   ```
   (confirm actual template cache path for the pinned `NUCLEI_VERSION` before implementing —
   don't assume `/root/.config/nuclei/templates` without checking).
2. Decide whether to also add retry logic around `-update-templates` (e.g. 2-3 attempts
   with backoff) to reduce flakiness from transient network/rate-limit issues, or whether
   failing loudly and letting the CI job's normal retry/re-run cover it is sufficient.
3. Consider whether CI should cache the Docker build layer (e.g. `docker/build-push-action`
   with GHA cache) to avoid re-fetching templates on every run — separate optimization,
   not required to fix the silent-failure bug, but would reduce how often this flake
   triggers at all.

## Out of scope

- No production/cloud deployment changes — this is a `docker/Dockerfile.local` /
  `tests/test_container.py` fix only.
- Not blocking any currently-merged work (PR #17 is unrelated in content; this failure
  surfaced on `main` post-merge, not on the PR itself).

## Open questions for the architect

1. Confirm the template cache path for pinned `NUCLEI_VERSION=v3.4.10` before writing
   the verification check (varies by Nuclei version/config).
2. Add retry logic, or rely on manual CI re-run when this flakes?
3. Worth adding Docker build layer caching to `ci.yaml` as a follow-up, or leave that
   as a separate task?
