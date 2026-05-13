# Seed Document Revision — v1.1 → v1.2 (delta)

> **APPLIED 2026-05-07** — folded into `LeanSecurity_Nuclei_seed_document.md` as
> part of the local-container-rebuild PR (Step 9 of `plan.md`). This file is
> retained for historical reference; do not apply again.

The following changes apply to the seed document when integrating ADR-007.
This file is a delta, not a replacement; apply each section in place.

---

## §10 Locked Design Decisions — replacements

### Remove

- ~~"Container entrypoint is bash. `docker/entrypoint.sh` does not parse YAML, does not invoke `scan.py`, runs Nuclei directly with hardcoded flags. The container is shell-native with cloud CLIs installed and stays that way."~~
- ~~"`profiles.yaml` is source of truth. `scan.py` parses it at runtime; `entrypoint.sh` hardcodes the equivalent flags. Drift is a bug."~~

### Add

- **Container entrypoint is split between bash and Python.** `docker/entrypoint.sh` is a thin bash wrapper for cloud I/O dispatch (`download_config`, `upload_results`, `CLOUD_PROVIDER` switch). It validates required environment, fetches `targets.txt` in cloud modes, then invokes `python -m scanner.scan ${CLIENT}` for the actual scan. The bash layer does not parse YAML and does not loop over profiles. YAML parsing is exclusive to `nuclei_helpers.py`. **Supersedes the v1.1 "container is bash-only" decision; see ADR-007.**
- **`profiles.yaml` is the single source of truth.** `scan.py` parses it; the container invokes `scan.py`; the local CLI invokes `scan.py`. There is no second copy of the profile flags anywhere in the repository. Adding a profile is a one-file change to `profiles.yaml`. The drift surface that existed in v1.1 has been eliminated structurally.
- **Container base image is `python:3.12-slim`.** Nuclei binary is downloaded and installed at a pinned version (build arg `NUCLEI_VERSION`). This matches the `vmctl` container's base image. Both containers in the repository share the same base.

---

## Runtime Language Policy — revision

### v1.1 wording (current)

> The scanner layer is **Python**. The container entrypoint is **bash**. This split is deliberate and locked:
>
> - **Application runtime code** (`scanner/`, `tests/`) — Python 3.12. Readable, testable, parses YAML directly, participates in CI.
> - **Container entrypoint** (`docker/entrypoint.sh`) — bash. The container is shell-native with cloud CLIs installed. Adding a Python runtime to the image buys nothing. Entrypoint hardcodes Nuclei flags; it does not parse YAML and does not invoke `scan.py`.
> - **Bootstrap / developer tooling** (`setup.sh`, pre-commit hooks) — bash. One-time setup that runs before any Python environment exists.
>
> Adding new shell scripts to `scanner/` is prohibited. Application runtime code is Python.

### v1.2 wording (this revision)

> The scanner layer is **Python**. The container runs **both Python and bash**, with a deliberate split:
>
> - **Application runtime code** (`scanner/`, `tests/`) — Python 3.12. Readable, testable, parses YAML directly, participates in CI. Same code runs in local CLI mode and inside the container.
> - **Container scan runtime** — Python. The container invokes `python -m scanner.scan ${CLIENT}`, which is the same `scan.py` the local CLI runs. There is no separate scan implementation for the container.
> - **Container I/O wrapper** (`docker/entrypoint.sh`) — bash. Handles `CLOUD_PROVIDER` dispatch, `download_config`, and `upload_results` using cloud CLIs (`gcloud`, `aws`, `az`) which are bash-native. The wrapper does not parse YAML and does not loop over profiles. After cloud I/O setup, the wrapper exec's `scan.py`.
> - **Bootstrap / developer tooling** (`setup.sh`, pre-commit hooks) — bash. One-time setup that runs before any Python environment exists.
>
> Adding new shell scripts to `scanner/` is prohibited. Adding scan logic to `entrypoint.sh` is prohibited — `entrypoint.sh`'s scope is cloud I/O only.

---

## Current Components table — revision

The "Container" row changes:

### v1.1

| Container | `docker/Dockerfile` + `docker/Dockerfile.local` + `docker/entrypoint.sh` | Volume-mounted local mode | Complete |

### v1.2

| Container | `docker/Dockerfile` + `docker/Dockerfile.local` + `docker/entrypoint.sh` | Volume-mounted local mode; runs `scan.py` inside the image | Rebuilt under ADR-007 |

---

## Interface Contracts — Source of Truth — addition

After the existing "Entrypoint environment variables (container modes only)" subsection, add:

### Container scan invocation

The container's bash wrapper invokes `python -m scanner.scan ${CLIENT}` after cloud I/O setup completes. The `scan.py` execution inside the container is identical to local CLI execution: same code path, same profile parsing, same output shape. The container is a deployment vehicle for `scan.py`, not a separate implementation.

### Removed environment variables

- `PROFILES_PATH` — `profiles.yaml` is now baked into the image at build time. Profile changes ship via image rebuild, which the existing CI workflow already handles.

### Required environment variables (container modes — all)

- `CLIENT` — the deployment name; matches a directory under `deployments/<client>/`. Validated at entrypoint start; missing or empty `CLIENT` causes the entrypoint to exit non-zero with a clear error.

---

## Boundary Rules — Enforced — addition

Add to the existing list:

- `entrypoint.sh` does not invoke `nuclei` directly. It invokes `scan.py`. Direct `nuclei` calls in `entrypoint.sh` are prohibited.
- `entrypoint.sh` does not loop over profiles. Profile iteration is `scan.py`'s responsibility, exclusively.
- `entrypoint.sh` does not parse YAML. YAML parsing is exclusive to `nuclei_helpers.py`.
- The container does not download `profiles.yaml` at runtime. Profiles are baked into the image at build time.

---

## §12 Change Log — new entry

| Version | Date | Change |
|---|---|---|
| 1.2 | 2026-05-05 | ADR-007 integrated. Container layer rebuilt: `python:3.12-slim` base, Nuclei binary at pinned version, `scan.py` invoked from a thin bash wrapper. The "container is bash-only" v1.1 decision is reversed. The "drift between profiles.yaml and entrypoint.sh is a bug" v1.1 decision is replaced by structural elimination of the drift surface — `profiles.yaml` is now the single source of truth with no parallel hardcoded copy. `PROFILES_PATH` env var removed; profiles bake into the image. |
