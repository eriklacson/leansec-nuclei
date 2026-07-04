# Scope — dockerfile-template-verification

Source: `.claude/tasks/dockerfile-template-verification.md`. Read per CLAUDE.md execution
loop step 1 (READ).

## 1. What the task asks for

`docker/Dockerfile.local:25-27` bakes Nuclei templates into the image at build time so that
`UPDATE_TEMPLATES=false` works offline (used by CI/tests and air-gapped deployments). The
`RUN nuclei -update-templates -silent` step can silently produce an image with zero templates
(transient network failure, GitHub rate limit) without failing the build — there's no
verification step. This caused `tests/test_container.py::test_local_mode_produces_canonical_jsonl_and_normalized_json`
to fail on the post-merge `main` CI run after PR #17 (`gh run view 28644556374`), unrelated to
that PR's actual (docs/Terraform-only) content — pure CI flake exposed by this gap.

Fix: add a build-time check that fails loudly if no templates were fetched, instead of
silently shipping an empty template cache.

## 2. Current state (verified against the repo and a local Nuclei install, not assumed)

- **Template cache path confirmed by direct verification**, not doc-guessing: nuclei v3.4.10
  (same version pinned in `docker/Dockerfile.local:9`, `ARG NUCLEI_VERSION=v3.4.10`) was already
  installed locally. Running `nuclei -update-templates -silent` and inspecting
  `~/.config/nuclei/.templates-config.json` shows:
  ```json
  "nuclei-templates-directory": "/home/<user>/nuclei-templates"
  ```
  **Templates land at `$HOME/nuclei-templates`, not `$HOME/.config/nuclei/templates`** (the
  original task file's placeholder guess). Verified 13,416 `.yaml` files actually present under
  that path after the update. `~/.config/nuclei/` itself only holds `config.yaml`,
  `.templates-config.json`, `.nuclei-ignore`, `reporting-config.yaml` — no templates.
- **No `USER` directive anywhere in `docker/Dockerfile.local`** — the image runs as root for
  every layer, build and runtime alike (only `WORKDIR /app` is set). So `HOME=/root` is
  consistent between the build-time `RUN nuclei -update-templates -silent` step and the
  container's runtime execution of `entrypoint.sh` → `scan.py` → `nuclei`. No root/non-root
  HOME-mismatch risk to design around — the verification check added at build time checks the
  same path Nuclei will read from at runtime.
- **CI has no Docker layer caching** (`.github/workflows/ci.yaml` — hosted runners are fresh
  VMs), confirmed by grep: no `cache`/`buildx` directives around the `docker build` step in
  `tests/test_container.py`'s `built_image` fixture. Every CI run does a fully uncached
  `docker build`, so `-update-templates` hits the network fresh every single run — this is
  what makes the failure mode reachable at all (not a one-off local build issue).
- **`-silent` does not appear to propagate a nonzero exit code on a failed/empty template
  fetch** — this is the actual gap. `docker build`'s `RUN` step only fails on a nonzero exit
  from the command; if `nuclei -update-templates -silent` exits 0 despite fetching nothing,
  the build layer succeeds and gets cached/pushed with an empty template directory.

## 3. What does NOT change (per task file, confirmed no conflict with current repo)

- No production/cloud deployment changes — `infra/gcp/`, `scanner/scan.py`, and cloud entrypoint
  logic are untouched. This is scoped to `docker/Dockerfile.local` and, if a regression test is
  added, `tests/test_container.py`.
- No CSFLite control mapping changes — this is CI/build tooling, produces no scan output.
- Not blocking or related to the already-merged PR #17 — that PR's content (ADR-008, docs,
  Terraform templates) is unaffected by and unrelated to this fix.

## 4. Open questions from the task file — status

| # | Question | Resolution needed from architect |
|---|---|---|
| 1 | Confirm template cache path for `NUCLEI_VERSION=v3.4.10` | **Resolved during READ** — `$HOME/nuclei-templates` (`/root/nuclei-templates` in the container), verified directly, not assumed. See §2. |
| 2 | Add retry logic around `-update-templates`, or rely on manual CI re-run? | Still open — architect decision, see plan.md. |
| 3 | Add Docker build layer caching to `ci.yaml` as a follow-up, or separate task? | Still open — architect decision, see plan.md. |
