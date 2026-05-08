# PR Scope: Local Container Rebuild (v0.2)

Source: `.claude/docs/project.yaml` (`name: local-container-rebuild`, `mode: build`)

## What this PR does

Rebuild the **local Docker image only** (`docker/Dockerfile.local` + shared `docker/entrypoint.sh`) so that local-CLI and local-Docker modes produce byte-identical outputs. The cloud Dockerfile is explicitly deferred to a follow-up PR.

## Why

Four concrete defects in the current container layer against the seed document:

1. `COPY ../scanner/profiles/` in both Dockerfiles is invalid Docker syntax and cannot succeed under any documented build context.
2. `entrypoint.sh` writes JSONL filenames (`identity_`, `transport_`, `owasp_top10_`) that diverge from `profiles.yaml` profile names — the exact "drift between profiles.yaml and entrypoint.sh" failure mode the seed document calls a bug.
3. The container produces only raw JSONL. The local CLI (`scan.py`) produces both raw JSONL and consolidated normalized JSON. Two runtimes, two output shapes — violates the architectural intent that local CLI and local container are interchangeable.
4. There is no canonical `docker run` invocation documented. Local Docker mode is effectively undocumented.

## Architectural shift (ADR-007)

Supersedes the locked seed-document decision "Container entrypoint is bash, no YAML parsing".

**New model:** bash wrapper handles cloud I/O dispatch; `scan.py` handles scan execution and YAML parsing. Single source of truth for scan logic across local CLI and container modes — the drift surface no longer exists.

## In scope (deliverables)

| Path | Purpose |
|---|---|
| `docker/Dockerfile.local` | Rewrite on `python:3.12-slim`, pin `NUCLEI_VERSION=v3.4.10` (verify before merge), build context = repo root, `pip install pyyaml` only (no Poetry, no cloud CLIs) |
| `docker/entrypoint.sh` | Thin bash wrapper. Validates env, dispatches cloud I/O, invokes `scan.py`. Cloud branches (gcp/aws/azure) present but unexercised by this PR |
| `.dockerignore` | At repo root. Excludes `results/`, `.git/`, `.venv/`, `__pycache__`, live `deployments/<client>/` (except `_example/`), `infra/`, `tests/`, `pyproject.toml`, `poetry.lock` |
| `tests/test_container.py` | Docker-gated smoke tests; session-scoped build fixture |
| `decisions/ADR-007-python-in-container.md` | Already drafted; ships in this PR |
| `README.md` | Add canonical Local Docker section parallel to Local CLI |

Also: add `UPDATE_TEMPLATES` env var (default `true`); remove `PROFILES_PATH` (profiles are baked in).

## Out of scope (explicit)

- `docker/Dockerfile` (cloud image) — deferred to a follow-up `project.yaml`
- `infra/gcp/workflows/scanner-image.yml` build-context fix — deferred with the cloud Dockerfile rebuild (workflow currently builds with context = `docker/`, which cannot resolve `COPY scanner/` paths and will break against any rebuilt cloud Dockerfile)
- Cloud-mode E2E validation (Cloud Run job + Cloud Scheduler + Conduit ingest)
- AWS/Azure E2E validation (case blocks present in entrypoint but unexercised)
- `vmctl` container (`docker/Dockerfile.vmctl`) — separate component
- Conduit intake bucket path migration (ADR-006) — Conduit-owned, cross-project
- Multi-stage build / single-Dockerfile collapse — explicitly rejected
- Local Quickstart `.docx` update — pending re-draft after SLO tracking component is scoped

## Acceptance bars

**Build**
- `docker build -f docker/Dockerfile.local -t leansecurity/nuclei-scanner:local .` succeeds from repo root with exit 0
- Built image size < 300MB
- `nuclei -version` returns the pinned `NUCLEI_VERSION`
- `python --version` returns 3.12.x
- `/app/scanner/profiles/profiles.yaml` is present and valid

**Entrypoint validation**
- Missing `CLIENT` → non-zero exit with clear error
- Unsupported `CLOUD_PROVIDER` → non-zero exit
- `CLIENT` pointing at non-existent deployment → non-zero exit with clear error
- `CLOUD_PROVIDER=local` with valid mounts → runs to completion
- `UPDATE_TEMPLATES=false` skips template refresh

**Output parity (the central goal)**
- Local CLI and local Docker produce file outputs at identical paths with identical filenames for an identical `targets.txt`
- Filenames use canonical profile names from `profiles.yaml` (`baseline_web`, `patch_cve`, `identity_remote_access`, `data_protection`, `transport_security`, `owasp_top10_core`, `vuln_monitoring`)
- No filename in either mode reads `identity_*.jsonl`, `transport_*.jsonl`, or `owasp_top10_*.jsonl` — the legacy mismatch is gone
- Both modes produce `result-YYYY-MM-DD.json` normalized output

**CI compatibility**
- `.github/workflows/ci.yaml` continues to pass (no scanner-layer code changed)
- `tests/test_container.py` is included in the pytest suite, gated by Docker availability
- `infra/gcp/workflows/scanner-image.yml` is **not** expected to pass (targets cloud Dockerfile, not touched by this PR)

## Implementation order

1. Verify `NUCLEI_VERSION=v3.4.10` against the releases page; bump if needed
2. Commit `decisions/ADR-007-python-in-container.md`
3. Add `.dockerignore` at repo root
4. Rewrite `docker/Dockerfile.local`
5. Rewrite `docker/entrypoint.sh` (local branches exercised; cloud branches present but unexercised)
6. Add `tests/test_container.py`
7. Verify acceptance criteria
8. Update `README.md` with Local Docker section
9. Open PR; merge gates on CI green and architect approval

## Follow-up work (NOT this PR)

- **cloud-container-rebuild** — rewrite `docker/Dockerfile` on the same `python:3.12-slim` base with cloud CLIs, fix `scanner-image.yml` build context, run Cloud Run E2E. Blocked by this PR landing and stabilizing.
- **seed-document-v1.2-revision** — fold the drafted delta into §10 Locked Design Decisions, Runtime Language Policy, Component Registry, §12 Change Log. Blocked by SLO tracking (`vmctl`) component scope finalization.
