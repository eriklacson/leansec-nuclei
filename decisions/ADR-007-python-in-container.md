# ADR-007: Python carryover into the scanner container

- **Status:** Proposed
- **Date:** 2026-05-05
- **Supersedes:** Locked Design Decision §10 of seed document v1.1 — "Container entrypoint is bash. `docker/entrypoint.sh` does not parse YAML, does not invoke `scan.py`, runs Nuclei directly with hardcoded flags."
- **Related:** ADR-006 (scanner output path migration — cross-project, Conduit-owned)
- **Architect:** Erik
- **Consulted:** —

## Context

The seed document v1.0 locked the container entrypoint as bash-only. The rationale was sound at the time: the local CLI (`scan.sh`) and the container entrypoint (`entrypoint.sh`) were both bash scripts running the same Nuclei invocations against the same profiles. Two scripts, identical structure, easy to keep in sync. The container image was built on `projectdiscovery/nuclei`, which is shell-native; adding a Python runtime bought nothing.

Three things have changed since:

1. **The local CLI migrated from `scan.sh` to `scan.py`.** The scanner layer now parses `profiles.yaml` at runtime via `nuclei_helpers.load_profiles()`, builds Nuclei argv lists in Python, and produces a consolidated normalized JSON output (`result-YYYY-MM-DD.json`) alongside the raw JSONL. Adding a profile is a one-file change to `profiles.yaml`; `scan.py` requires no modification.

2. **The container did not migrate.** `entrypoint.sh` still hardcodes seven Nuclei invocations with literal flag strings. Profile filenames in the entrypoint (`identity_`, `transport_`, `owasp_top10_`) do not match the canonical profile names in `profiles.yaml` (`identity_remote_access`, `transport_security`, `owasp_top10_core`). This is the exact "drift between profiles.yaml and entrypoint.sh" failure the seed document explicitly classifies as a bug.

3. **The container does not produce normalized JSON.** Local CLI and local Docker now produce different output shapes for the same scan — a violation of the architectural intent that the two modes are interchangeable. Downstream consumers (vmctl, Conduit P2 ingest) face two output contracts depending on which mode produced the scan.

The locked decision was protecting against script duplication. In practice, the migration to Python created a worse drift surface: two different runtimes producing two different output shapes, with the bash side actively buggy. The decision now produces the harm it was meant to prevent.

## Decision

The container entrypoint is restructured into two layers:

- **Bash wrapper (`docker/entrypoint.sh`)** — handles cloud I/O dispatch (`download_config`, `upload_results`, `CLOUD_PROVIDER` switch). Cloud CLIs (`gcloud`, `aws`, `az`) are bash-native; this layer stays bash. The wrapper validates required environment, fetches `targets.txt` (cloud modes), invokes the scan, then uploads results (cloud modes). It does not parse YAML. It does not loop over profiles.

- **Python scan runtime (`scanner/scan.py` + `scanner/nuclei_helpers.py`)** — invoked by the bash wrapper as `python -m scanner.scan ${CLIENT}`. This is the same code that runs in local CLI mode. It parses `profiles.yaml`, executes profiles via `subprocess`, handles per-profile failures, writes raw JSONL, produces the consolidated normalized JSON.

The base image changes from `projectdiscovery/nuclei:latest` to `python:3.12-slim`. The Nuclei binary is downloaded and installed in the Dockerfile at a pinned version (build arg `NUCLEI_VERSION`). This matches the planned `vmctl` container's base image.

`profiles.yaml` is baked into the image at build time. The `PROFILES_PATH` environment variable and runtime profile download from `CONFIG_BUCKET` are removed. Profile changes ship via image rebuild, which the existing CI workflow (`infra/gcp/workflows/scanner-image.yml`) already triggers on `scanner/profiles/**` changes.

## What this supersedes — explicitly

The following statements from the seed document v1.1 §10 ("Locked Design Decisions") are reversed:

| v1.1 (superseded) | v1.2 (this ADR) |
|---|---|
| "Container entrypoint is bash. Does not parse YAML, does not invoke `scan.py`, runs Nuclei directly with hardcoded flags." | "Container entrypoint is a thin bash wrapper for cloud I/O dispatch; scan execution is delegated to `scanner/scan.py`. The container does not parse YAML at the bash layer; YAML parsing is exclusive to `nuclei_helpers.py`, same as local CLI mode." |
| "`profiles.yaml` is source of truth. `scan.py` parses it at runtime; `entrypoint.sh` hardcodes the equivalent flags. Drift is a bug." | "`profiles.yaml` is the single source of truth. `scan.py` parses it; the container invokes `scan.py`. The drift surface no longer exists." |
| "The container is shell-native with cloud CLIs installed and stays that way." | "The container has both Python (for scan execution) and cloud CLIs (for storage I/O). The runtime split is deliberate: Python where Python is the host language; bash where cloud SDKs are bash-native." |

## What this preserves — explicitly

These boundary rules are reaffirmed:

- **`scanner/` does not import from `docker/`, `infra/`, or any future component.** The scanner layer's runtime dependencies remain Python 3.12, `pyyaml`, and the `nuclei` binary on `PATH`. The container imports from `scanner/`, not the other way around.
- **`docker/` does not import from `infra/`.** The bash wrapper reads environment variables only.
- **Local first.** Local CLI and local Docker remain first-class deployment modes with identical output.
- **Ephemeral containers.** Cloud mode containers are still ephemeral; the Python addition does not introduce persistent state.
- **Cloud storage is the Conduit bridge.** No change to the scanner-Conduit boundary.

## Consequences

### Positive

- **Single source of truth for scan logic.** `scan.py` is the only thing that runs Nuclei. The "drift between `profiles.yaml` and `entrypoint.sh`" bug class is eliminated structurally, not by discipline.
- **Single output contract.** Local CLI and local Docker produce byte-identical files in identical paths. Downstream consumers see one shape.
- **Profile additions are one-file changes.** Edit `profiles.yaml`, rebuild the image. No bash sync step.
- **Test coverage extends to the container.** `tests/test_nuclei_helpers.py` already covers what runs inside the container. The bash wrapper's surface shrinks to a few dozen lines of cloud I/O, easily covered by smoke tests.
- **Image base aligned with `vmctl`.** Both containers in the repo run on `python:3.12-slim`. Single base image to track for security updates.

### Negative

- **Image size grows.** `projectdiscovery/nuclei:latest` is ~80MB. `python:3.12-slim` + Nuclei binary + pyyaml lands around ~200MB; with cloud CLIs (full Dockerfile) closer to ~500MB. Cloud Run cold starts add ~1–2s. For monthly scheduled scans this is invisible; for ad-hoc reruns it is noticeable but not blocking.
- **Two runtimes in one image.** Bash and Python coexist. The bash surface stays small (cloud I/O only) but is not zero.
- **Nuclei version is now our problem.** Switching off `projectdiscovery/nuclei:latest` means we own the binary install and the version pin. Upgrades require updating `NUCLEI_VERSION`, rebuilding, and re-running smoke tests.
- **Seed document revision required.** The Locked Design Decisions list and the language/runtime policy section both need updating in v1.2. Until that revision lands, the seed document and the codebase disagree.

### Neutral / accepted

- **`PROFILES_PATH` env var removed.** Profiles ride with the image. To change profiles, rebuild and redeploy. This matches CI behavior already in place and aligns with the principle that infrastructure changes go through CI/CD, not runtime configuration.
- **CI build context change.** `infra/gcp/workflows/scanner-image.yml` builds with `docker/` as context today; the new Dockerfiles need repo root context to `COPY scanner/`. Workflow must update — handled by the cloud follow-up project.yaml, not this PR.

## Alternatives considered

### Alternative A — Keep bash, fix the bugs in place

Fix the `COPY ../scanner/profiles/` paths, sync the profile filenames, document the divergence (raw JSONL only — Option A from the prior conversation). The container stays bash-native.

Rejected because:
- It accepts permanent divergence between local CLI and local Docker output shapes.
- It leaves the `profiles.yaml` ↔ `entrypoint.sh` drift surface intact — the bug class is preserved, just patched.
- It blocks vmctl and other consumers from a single ingestion path.

### Alternative B — Python-only entrypoint

Drop the bash wrapper entirely. `scan.py` grows a `--cloud-provider` flag and calls Python cloud SDKs (google-cloud-storage, boto3, azure-storage-blob).

Rejected because:
- It couples `scanner/` to cloud SDKs, violating the boundary rule that the scanner layer is cloud-unaware.
- Python cloud SDKs are heavyweight; image size impact is worse than Shape 1.
- Cloud CLIs are battle-tested for the storage operations involved (`cp`, `download`, `upload`); reimplementing in Python adds surface for marginal gain.

### Alternative C — Container shells out to scan.py via Poetry

Same as the chosen approach but the container installs Poetry and runs `poetry run python scanner/scan.py <client>`.

Rejected because:
- Poetry is dev-time tooling. The runtime image needs `pyyaml` and that's it. Installing Poetry in the image adds ~50MB and a dependency-resolution step at build time for no runtime benefit.
- `pip install pyyaml==<pinned>` from the Dockerfile is simpler and more auditable.

## Implementation

See `project.yaml` (local-container-rebuild) for the implementation spec, deliverables, acceptance criteria, and resolved questions. This ADR governs the architectural reversal; the project.yaml governs the build.

## Seed document revisions required

When the next seed document revision (v1.2) is published:

1. **§10 Locked Design Decisions** — replace the three entries listed in "What this supersedes" above with the v1.2 wording.
2. **Runtime Language Policy section** — revise to acknowledge that the container runs both bash (cloud I/O) and Python (scan execution). Bash is no longer the sole container runtime.
3. **Repository Structure / docker/ section** — note that `docker/Dockerfile.local` and `docker/Dockerfile` both build on `python:3.12-slim` with Nuclei layered in, not on `projectdiscovery/nuclei`.
4. **§12 Change Log** — add v1.2 entry referencing this ADR.

Per system instruction, the seed document is not re-drafted piecemeal — this revision waits for SLO tracking component (vmctl) scope finalization. A v1.2 delta is drafted as a separate artifact (`seed-document-v1.2-delta.md`) for folding into the eventual re-draft.
