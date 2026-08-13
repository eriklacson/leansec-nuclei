# # LeanSecurity — Nuclei
## Project Seed Document v1.6
**Classification:** LeanSecurity Internal IP
**Status:** Container layer rebuilt under ADR-007 (May 2026); scanner layer Python; normalized JSON output wrapped in v1 envelope (May 2026); client-owned repo topology added under ADR-008 and its IAM gaps fixed (August 2026); Month 1 build complete
**Last updated:** August 2026

---

## 1. What This Is

Nuclei is LeanSecurity's standard external vulnerability scanning pipeline. It takes a client's list of public-facing URLs and IPs, runs CSFLite-aligned scan profiles against them using the open-source Nuclei scanner, and produces date-partitioned JSONL output. That output feeds two consumers: the client's vulnerability register (for operational triage and SLO tracking) and LeanSecurity's Conduit governance platform (for automated CSFLite scoring against DE.CM-08).

The baseline operating mode is a local CLI scan run from the consultant's machine — `python scanner/scan.py <client>` — with results pushed to cloud storage manually when ready for Conduit ingestion. The pipeline can be escalated to containerized and fully automated cloud deployments without changing the scan logic, profiles, or output format.

This is LeanSecurity internal IP. It is not a required client deliverable. Clients receive scan results and remediation guidance, or use the pipeline as part of a consulting engagement. 

The first proof-of-concept deployment is for an active client engagement. Two GCP deployment topologies exist (see ADR-008): the default, where the client's deployment lives under `deployments/<client>/` in this repository and the client does not own or modify the scanner, infrastructure modules, or CI/CD workflows; and a client-owned topology, where the client operates their own private repo (scaffolded from `infra/gcp/client-repo-template/`) with its own CI/CD, while the scanner and `infra/gcp/` Terraform module remain consumed by reference, never forked or edited.

### Project Separation

| Project | Asset Type | Owns |
|---|---|---|
| `LeanSecurity — CSFLite` | Framework IP | Control definitions, weights, scoring methodology. Nuclei consumes `controls.yaml` via the `csf_subcategory` field in profiles.yaml it does not define or modify controls. |
| `LeanSecurity — [Client]` | Client delivery | Client engagement context, P2 Solution Architecture, Vulnerability Management Program policy, vulnerability register, remediation workflow. Nuclei is one implementation component within P2. |
| `LeanSecurity — Governance Pipeline` | Internal IP | Conduit platform, P2 ingest adapter, canonical event model, CSFLite scoring engine. Conduit P2 ingest adapter consumes Nuclei normalized JSON output from cloud storage. Nuclei does not write to Conduit directly. |
| `LeanSecurity — Nuclei` | Internal IP | Scanner layer (`scan.py`, `nuclei_helpers.py`, `profiles.yaml`), container builds (Dockerfiles, `entrypoint.sh`), Transformation layer (converts raw Nuclei JSONL to normalized JSON format for Conduit P2 ingest adapter), Infrastructure modules (Terraform per cloud vendor), client deployment templates, CI/CD workflows, JSONL output format specification. |

---

## 2. Architecture Pattern

**Progressive Deployment Scanner.** A local-first scanning engine that produces identical output across three deployment modes. The baseline is a Python CLI that parses `profiles.yaml` at runtime and invokes the Nuclei binary via subprocess and subsequent JSONL transformation procedure. Each escalation step (Docker, cloud automation) adds infrastructure around the same core scan logic without modifying it.

### Runtime Language Policy

The scanner layer is Python. The container runs **both Python and bash**, with a deliberate split (see ADR-007):

- **Application runtime code** (`scanner/`, `tests/`) — Python 3.12. Readable, testable, parses YAML directly, participates in CI (Black/Ruff/Bandit/pytest). Same code runs in local CLI mode and inside the container.
- **Container scan runtime** — Python. The container invokes `python /app/scanner/scan.py ${CLIENT}`, which is the same `scan.py` the local CLI runs. There is no separate scan implementation for the container.
- **Container I/O wrapper** (`docker/entrypoint.sh`) — bash. Handles `CLOUD_PROVIDER` dispatch, `download_config`, and `upload_results` using cloud CLIs (`gcloud`, `aws`, `az`) which are bash-native. The wrapper does not parse YAML and does not loop over profiles. After cloud I/O setup, the wrapper invokes `scan.py`.
- **Bootstrap / developer tooling** (pre-commit hooks) — bash. One-time setup that runs before any Python environment exists.

### Deployment Modes

| Mode | Dependencies | Execution | Results Storage | Conduit Integration | When to Use |
|---|---|---|---|---|---|
| **Local CLI** (baseline) | Python 3.12, Nuclei binary, `pyyaml` | `poetry run python scanner/scan.py <client>` (or `python scanner/scan.py <client>`) | Local filesystem: `results/<client>/YYYY-MM/` | Manual `gcloud storage cp` to GCS | Initial engagement scans, proof-of-concept, ad-hoc assessments |
| **Local Docker** (escalation 1) | Docker runtime | `docker run` with volume mounts | Local filesystem via volume mount | Manual `gcloud storage cp` to GCS | Reproducible environment needed, no Nuclei install on host |
| **Cloud Automated** (escalation 2) | Terraform + cloud account | Cloud scheduler triggers ephemeral container | Cloud object storage (GCS/S3/Blob) | Automatic — Conduit reads from bucket | Ongoing monthly automated scans, steady-state operations |

All three modes scan the same target list and produce identical JSONL output. The mode determines how the scan is triggered, where config is read from, and where results are written — not what is scanned or how findings are formatted.

Note on `profiles.yaml`: it is the single source of truth across all modes. `scan.py` parses it at runtime via `nuclei_helpers.load_profiles()`, and the container invokes the same `scan.py`. There is no second copy of the profile flags anywhere in the repository (see ADR-007).

### Layers

**Scanner Layer (local CLI — Python + Nuclei binary)**
Runs the Nuclei binary against a client target list using 7 CSFLite-aligned profiles. Reads targets from `deployments/<client>/targets.txt`. Parses profile definitions from `scanner/profiles/profiles.yaml` at runtime. Writes JSONL to `results/<client>/YYYY-MM/`. This is the complete, functional scanning capability. Everything above this layer is optional infrastructure. Owns: `scanner/scan.py`, `scanner/nuclei_helpers.py`, `scanner/profiles/profiles.yaml`. Never touches: Docker, cloud storage, Terraform, Conduit. Runtime dependencies are constrained to Python 3.12, `pyyaml`, and the `nuclei` binary — no cloud SDKs, no Docker awareness.

**Container Layer (escalation 1 — requires Docker)**
Wraps the scanner in a Docker image built on `python:3.12-slim` with the Nuclei binary at a pinned version (`NUCLEI_VERSION` build arg). The entrypoint script (bash) dispatches storage download/upload based on a `CLOUD_PROVIDER` environment variable (`local`, `gcp`, `aws`, `azure`), then invokes `python /app/scanner/scan.py ${CLIENT}` — the same `scan.py` the local CLI runs. In `local` mode, config and output are volume-mounted — no cloud credentials needed. The runtime split (bash for cloud I/O, Python for scan execution) is deliberate; see ADR-007. Owns: `docker/Dockerfile`, `docker/Dockerfile.local`, `docker/entrypoint.sh`. Never touches: Terraform, CI/CD, scan profile definitions.

**Infrastructure Layer (escalation 2 — requires Terraform + cloud account)**
Provisions cloud resources (compute, storage, scheduler, IAM) via Terraform modules, one per cloud vendor. Each module exposes the same variable interface so client deployments are cloud-portable. Owns: `infra/gcp/`, `infra/aws/`, `infra/azure/`. Never touches: scan logic, Docker builds, profile definitions.

**Deployment Layer (shared across all modes)**
Per-client configuration: target list and (for cloud mode) Terraform variables and state backend. One folder per client under `deployments/`.

---

## 3. Interface Contracts

### scan.py — Local CLI Interface

The primary interface. Consumed by the operator (consultant). Positional client argument, no environment variables, no config files beyond the target list.

| Input/Output | Path | Format | Description |
|---|---|---|---|
| Input: target list | `deployments/<client>/targets.txt` | Plain text, one URL/IP per line, `#` comments | Pre-populated by LeanSecurity per client. |
| Input: profiles | `scanner/profiles/profiles.yaml` | YAML, parsed at runtime | Source of truth. `scan.py` uses `nuclei_helpers.load_profiles()` to parse this file and iterates profiles dynamically. |
| Output: results | `results/<client>/YYYY-MM/*.jsonl` | JSONL, one file per profile | Date-partitioned by scan month. Gitignored. |
| Output: console | stdout | Text | Progress indicators (`[1/7] baseline_web`) and summary (total findings count). |

**Invocation:**
```
poetry run python scanner/scan.py <client-name>
```
or (with a Python 3.12 virtualenv already active):
```
python scanner/scan.py <client-name>
```

**Exit behavior:** Each profile is executed inside a `try/except` block. A profile that finds zero matches exits cleanly (empty JSONL file). A profile that fails (unreachable target, template error, non-zero Nuclei exit) is caught and logged — remaining profiles still execute. This is the Python equivalent of the `|| true` semantics used by the container entrypoint.

**Runtime dependencies:** Python 3.12, `pyyaml`, and the `nuclei` binary on `PATH`. No cloud SDKs, no Docker awareness, no Terraform knowledge.

### nuclei_helpers.py — Scanner Layer Internal API

Consumed by `scan.py` and any future Python code in the scanner layer. Not exposed outside `scanner/`. This is the runtime translation layer from `profiles.yaml` entries to Nuclei CLI invocations.

| Function | Returns | Purpose |
|---|---|---|
| `load_profiles(path)` | `dict` | Parse `profiles.yaml` into a dictionary. Raises `FileNotFoundError` on missing file, `yaml.YAMLError` on malformed YAML. |
| `get_profile(profiles_data, name, default=None, allow_null=False)` | `dict` or default | Retrieve a named profile from the parsed profiles dictionary. |
| `build_nuclei_cmd(profile, targets, output_path=None, scan_directory=None)` | `list[str]` | Construct the `nuclei` argv list from a profile definition and a target list path. Resolves output paths. Raises `TypeError` on non-dict profile, `ValueError` on empty target, `FileNotFoundError` on missing targets file. |
| `run_nuclei(cmd)` | `None` | Execute a Nuclei command via `subprocess`. Raises `subprocess.CalledProcessError` on non-zero exit. |

The library has one runtime dependency (`pyyaml`) and no awareness of the container or infrastructure layers. It is the only place in the scanner that parses YAML.

### profiles.yaml — Scan Profile Definition

Single source of truth for scan configuration. `scan.py` parses this file at runtime via `nuclei_helpers.load_profiles()`. The container invokes the same `scan.py`; there is no separate hardcoded copy of profile flags anywhere in the repository (see ADR-007). YAML parsing is exclusive to `nuclei_helpers.py`. `profiles.yaml` is baked into the container image at build time — to change profiles, edit the YAML and rebuild.

| Field | Type | Description |
|---|---|---|
| `version` | `int` | Schema version. Currently `1`. |
| `profiles.<n>.tags` | `list[string]` | Nuclei template tags to include. |
| `profiles.<n>.severity` | `list[string]` | Severity filter: `info`, `low`, `medium`, `high`, `critical`. |
| `profiles.<n>.csf_subcategory` | `list[string]` | CSFLite control IDs this profile provides evidence for. |
| `profiles.<n>.rate_limit` | `int` | Max requests per second. |
| `profiles.<n>.concurrency` | `int` | Max concurrent template executions. |
| `profiles.<n>.retries` | `int` | Retry count per template. |
| `profiles.<n>.timeout` | `int` | Per-request timeout in seconds. |
| `profiles.<n>.input_mode` | `string` | Nuclei input mode: `list` or `single`. |
| `profiles.<n>.output` | `string` | Default output filename. `scan.py` uses the stem and appends `_YYYY-MM.jsonl`. |
| `profiles.<n>.notes` | `string` | Human-readable description of what the profile checks. |

### Raw JSONL Output — Raw Scan Results

Produced by Nuclei. One JSON object per line per finding. Identical format regardless of deployment mode. Consumed by scan.py and tranformed to a normalized JSON format to be consumed by SLO tracking component (for later development).

| Field | Type | Description |
|---|---|---|
| `template-id` | `string` | Nuclei template identifier (e.g., `cve-2024-1234`). Maps to Vulnerability ID in register. |
| `info.name` | `string` | Human-readable vulnerability name. |
| `info.severity` | `string` | `critical` / `high` / `medium` / `low` / `info`. Determines SLA tier. |
| `host` | `string` | Target URL or IP that matched. Maps to Affected Asset in register. |
| `matched-at` | `string` | Specific URL or endpoint matched. Used for remediation targeting. |
| `timestamp` | `string` | ISO 8601 scan timestamp. Maps to Discovery Date in register. |
| `info.description` | `string` | Description of finding |

### Normalized JSON Output — Normalized Scan Results

Produced by `scan.py` (and by the standalone `scanner/nuclei_convert_tool.py` re-consolidation CLI). Consolidates the raw Nuclei JSONL output in `results/<client>/<YYYY-MM>/` into a single JSON document written to `results/<client>/<YYYY-MM>/result-<YYYY-MM-DD>.json`. Identical format regardless of deployment mode. Consumed by external integrations (third-party SLO trackers, dashboards, future Conduit P2 ingest). Sample normalized JSON: `.claude/docs/normalized_sample.json`.

The document is wrapped in a versioned envelope so consumers integrate against a stable, evolvable contract. The envelope replaces the previous bare-array shape — there is no backward-compatibility mode.

**Envelope shape:**

```json
{
  "schema_version": 1,
  "scan_run": {
    "client": "<client>",
    "run_date": "YYYY-MM-DD",
    "profiles_executed": ["<sorted profile names>"],
    "findings_count": 42
  },
  "findings": [ <normalized finding objects> ]
}
```

**Top-level fields:**

| Field | Type | Description |
|---|---|---|
| `schema_version` | `integer` | Envelope contract version. Currently `1`. Source of truth: `nuclei_json_converter.SCHEMA_VERSION`. |
| `scan_run` | `object` | Run-level metadata (see below). |
| `findings` | `array` | List of normalized finding objects (see "Finding object" table below). |

**`scan_run` fields:**

| Field | Type | Description |
|---|---|---|
| `client` | `string` | Client deployment name; matches a directory under `deployments/<client>/`. Passed in from the CLI. |
| `run_date` | `string` | ISO date (`YYYY-MM-DD`) when the consolidated document was produced. Computed by the caller (`scan.py` / `nuclei_convert_tool.py`), not by the envelope builder. |
| `profiles_executed` | `array[string]` | Profile names derived from the `*.jsonl` filenames present in the run directory. Sorted for deterministic output. |
| `findings_count` | `integer` | `len(findings)`. Provided for consumer convenience — the value is always equal to the length of the `findings` array. |

**Finding object (one entry per element in `findings[]`):**

| Field | Type | Description |
|---|---|---|
| `timestamp` | `string` | ISO 8601 scan timestamp. Maps to Discovery Date in register. |
| `host` | `string` | Maps to `host` in Raw JSON Output. |
| `template-id` | `string` | Maps to `template-id` in Raw JSON Output. |
| `info.name` | `string` | Maps to `info.name` in Raw JSON Output. |
| `matched-at` | `string` | Maps to `matched-at` in Raw JSON Output. |
| `info.severity` | `string` | Maps to `info.severity` in Raw JSON Output. |
| `description` | `string` | Maps to `info.description` (with fallback to `info.name`) in Raw JSON Output. |

The finding object shape is unchanged from the pre-envelope contract — only the outer container changed. Envelope construction is implemented in `scanner/nuclei_json_converter.build_normalized_document(...)`, which is pure (no I/O, no `datetime`, no env access); callers supply `run_date`.

### Local Results Directory — Filesystem Contract

Produced by `scan.py`. Consumed by the operator (manual review, manual push to GCS).

```
results/
└── <client>/
    └── YYYY-MM/
        ├── baseline_web_YYYY-MM.jsonl
        ├── patch_cve_YYYY-MM.jsonl
        ├── identity_remote_access_YYYY-MM.jsonl
        ├── data_protection_YYYY-MM.jsonl
        ├── transport_security_YYYY-MM.jsonl
        ├── owasp_top10_core_YYYY-MM.jsonl
        ├── vuln_monitoring_YYYY-MM.jsonl
        └── result-YYYY-MM-DD.json
```

The `results/` directory is gitignored. Scan results are never committed to the repository. The operator decides when and whether to push results to cloud storage for Conduit ingestion.

### Cloud Storage Directory — Bucket Contract

Produced by `docker/entrypoint.sh` (cloud mode) or manual `gcloud storage cp` (local mode). Consumed by Conduit P2 ingest adapter.

```
<results-bucket>/
└── <client>/
    └── YYYY-MM/
        ├── baseline_web_YYYY-MM.jsonl
        ├── ...
        ├── vuln_monitoring_YYYY-MM.jsonl
        └── result-YYYY-MM-DD.json
```

The directory structure mirrors the local results directory. Conduit reads from this path. Lifecycle rules (configurable via Terraform) transition to Nearline at 12 months and delete at 24 months.

### Entrypoint Environment Variables — Container Interface (Escalation 1+2)

Consumed by `docker/entrypoint.sh`. Not used in local CLI mode. Set by `docker run -e` flags (local Docker) or Terraform env blocks (cloud mode).

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `CLIENT` | `string` | Yes (all modes) | — | Deployment name; matches a directory under `deployments/<client>/`. Validated at entrypoint start; missing or empty `CLIENT` causes the entrypoint to exit non-zero. |
| `CLOUD_PROVIDER` | `string` | No | `local` | Dispatch target: `local`, `gcp`, `aws`, `azure`. Allowlisted at entrypoint start. |
| `CONFIG_BUCKET` | `string` | Cloud modes | — | Cloud storage path for config files. |
| `RESULTS_BUCKET` | `string` | Cloud modes | — | Cloud storage path for scan results. |
| `TARGETS_PATH` | `string` | No | `targets/targets.txt` | Path to target list within config bucket (cloud modes only). |
| `UPDATE_TEMPLATES` | `string` | No | `true` | Whether to run `nuclei -update-templates` at container start. Set `false` in CI / air-gapped runs. |

### Container Scan Invocation

The container's bash wrapper invokes `python /app/scanner/scan.py ${CLIENT}` after cloud I/O setup completes. The `scan.py` execution inside the container is identical to local CLI execution: same code path, same profile parsing, same output shape (raw JSONL plus consolidated `result-YYYY-MM-DD.json`). The container is a deployment vehicle for `scan.py`, not a separate implementation.

`profiles.yaml` is baked into the image at build time. The image rebuild on `scanner/profiles/**` change is wired in `.github/workflows/publish-image.yaml`. Runtime profile download (the v1.1 `PROFILES_PATH` env var) was removed in v1.2 — see ADR-007.

### Terraform Module Variables — GCP (Escalation 2)

Consumed by client deployment `main.tf`. Not used in local CLI or local Docker modes.

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `project_id` | `string` | Yes | — | Client GCP project ID. |
| `region` | `string` | No | `asia-southeast1` | GCP region for all resources. |
| `client_name` | `string` | Yes | — | Short client identifier. |
| `scanner_image` | `string` | Yes | — | Docker image URI in Artifact Registry. |
| `schedule_cron` | `string` | No | `0 2 1-7 * 0` | Cron expression for scan schedule. |
| `schedule_timezone` | `string` | No | `UTC` | Timezone for scheduler. |
| `targets_file` | `string` | Yes | — | Path to client target list file in repo. |
| `profiles_file` | `string` | No | `scanner/profiles/profiles.yaml` | Path to profiles.yaml in repo. |
| `results_retention_days` | `number` | No | `365` | Days before Nearline transition. |
| `results_delete_days` | `number` | No | `730` | Days before deletion. |
| `job_memory` | `string` | No | `2Gi` | Container memory allocation. |
| `job_cpu` | `string` | No | `1` | Container CPU allocation. |
| `job_timeout` | `string` | No | `3600s` | Container execution timeout. |
| `enable_scheduler` | `bool` | No | `true` | Provision Cloud Scheduler job + scheduler SA + invoker IAM binding. |
| `enable_wif` | `bool` | No | `false` | Provision a deployer SA, WIF pool, GitHub OIDC provider, and the assume binding (client-owned CI topology, ADR-008). Requires `wif_github_repository`. |
| `enable_ar_mirror` | `bool` | No | `false` | Provision an Artifact Registry repository mirroring the GHCR image. |
| `wif_github_repository` | `string` | Cond. | `""` | GitHub `owner/repo` authorized to assume the deployer SA via WIF. Required when `enable_wif = true`. |
| `state_bucket_name` | `string` | No | `""` | GCS bucket holding this deployment's Terraform state. When set alongside `enable_wif`, grants the deployer `objectAdmin` on it (defense-in-depth alongside `storage.admin`). |

### Terraform Module Outputs — GCP

| Output | Type | Description |
|---|---|---|
| `config_bucket_name` | `string` | Name of the config storage bucket. |
| `results_bucket_name` | `string` | Name of the results storage bucket. |
| `cloud_run_job_name` | `string` | Name of the Cloud Run job. |
| `scheduler_job_name` | `string \| null` | Name of the scheduler job; `null` when `enable_scheduler = false`. |
| `scanner_service_account_email` | `string` | Email of the scanner service account. Not the CI identity. |
| `deployer_service_account_email` | `string \| null` | Email of the deployer SA that client CI assumes via WIF; `null` when `enable_wif = false`. This is the client's `GCP_SA_EMAIL`. |
| `wif_pool_name` | `string \| null` | Full resource name of the WIF pool; `null` when `enable_wif = false`. |
| `wif_provider_name` | `string \| null` | Full resource name of the WIF GitHub provider; `null` when `enable_wif = false`. |
| `artifact_registry_repository` | `string \| null` | Full resource name of the mirrored AR repository; `null` when `enable_ar_mirror = false`. |

### Design Rules

- `profiles.yaml` is the single source of truth for scan configuration. `scan.py` parses it at runtime; the container invokes `scan.py`. There is no second copy of profile flags anywhere in the repository — adding a profile is a one-file change to `profiles.yaml` followed by an image rebuild.
- The scanner layer does not parse YAML outside of `nuclei_helpers.py`. `scan.py` delegates all profile parsing to helpers. The container's bash wrapper does not parse YAML.
- JSONL output format is defined by Nuclei, not by LeanSecurity. The field mapping above documents the fields we consume — Nuclei may emit additional fields that are ignored.
- The local results directory structure and the cloud storage directory structure are identical. `gcloud storage cp results/<client>/YYYY-MM/*.jsonl gs://<bucket>/nuclei/YYYY-MM/` is the bridge between local and cloud modes — no transformation required.
- Terraform module variable interfaces must be consistent across cloud vendors. `infra/aws/` and `infra/azure/` must accept the same required variables as `infra/gcp/` (with cloud-specific defaults).
- The entrypoint script never hardcodes client names, target URLs, or bucket names. All client-specific values come from environment variables.
- `scan.py` never hardcodes client names. The client name is the only argument, and all paths are derived from it.

---

## 4. Repository Structure

### `leansecurity-nuclei`

```
leansecurity-nuclei/
├── scanner/                          ← LOCAL CLI (baseline — Python + Nuclei)
│   ├── scan.py                       ← python scanner/scan.py <client>
│   ├── nuclei_helpers.py             ← YAML parsing + command builder
│   ├── nuclei_json_converter.py      ← Raw-JSONL → v1 envelope transformation
│   ├── nuclei_convert_tool.py        ← Standalone re-consolidation CLI
│   ├── upload_to_gcs.py              ← Manual GCS push CLI (consultant workflow)
│   ├── validate_profiles.py          ← Nuclei template-tag validator
│   └── profiles/
│       └── profiles.yaml             ← Source of truth for scan config
│
├── docker/                           ← ESCALATION 1: container builds
│   ├── Dockerfile                    ← Full image with cloud CLIs (escalation 2)
│   ├── Dockerfile.local              ← Lightweight image, no cloud CLIs (escalation 1)
│   └── entrypoint.sh                 ← CLOUD_PROVIDER dispatch logic (bash by design)
│
├── infra/                            ← ESCALATION 2: Terraform modules
│   ├── gcp/                          ← Implemented
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── _example/                 ← Template for architect-run topology (topology 1)
│   │   ├── client-repo-template/     ← Template for client-owned CI topology (topology 2, ADR-008) — copied to a private repo the CLIENT owns, not to this repo's .github/workflows/
│   │   └── README.md
│   ├── aws/                          ← Stubbed (README only)
│   └── azure/                        ← Stubbed (README only)
│
├── deployments/                      ← Per-client config (used by ALL modes, gitignored, no _example/ here)
│   └── <client>/                     ← Per-client deployment, created by copying the mode-specific template
│       ├── main.tf                   ← Escalation 2 only (copied from infra/gcp/_example/)
│       ├── backend.tf                ← Escalation 2 only
│       ├── terraform.tfvars          ← Escalation 2 only
│       └── targets.txt               ← Used by ALL modes
│
├── tests/                            ← pytest suite (scanner layer)
│   ├── test_nuclei_helpers.py
│   ├── test_nuclei_json_converter.py
│   ├── test_container.py
│   ├── test_upload_to_gcs.py
│   └── validation/                   ← Validation fixtures
│
├── .github/workflows/                ← Always-active CI
│   └── ci.yaml                       ← Black + Ruff + Bandit + pytest on every push/PR
│
├── pyproject.toml                    ← Poetry config — Python 3.12, pyyaml, dev tooling
├── poetry.lock
├── .pre-commit-config.yaml           ← Black, Ruff, Bandit, pytest hooks
├── .gitignore                        ← Excludes results/, .terraform/, tfstate, .venv/
└── README.md                         ← Three-mode quick start + CSFLite mapping
```

### Boundary Rules

- `scanner/` never imports from `docker/` or `infra/`. `scan.py` calls the `nuclei` binary via `subprocess`. It has no awareness of Docker, containers, cloud storage, or Terraform. Its only runtime dependencies are Python 3.12, `pyyaml`, and the `nuclei` binary on `PATH`. This is the complete scanning capability — everything else is optional infrastructure.
- `docker/` never imports from `infra/`. The entrypoint script reads environment variables — it does not know how those variables were set.
- `entrypoint.sh` does not invoke `nuclei` directly. It invokes `scan.py`. Direct `nuclei` calls in `entrypoint.sh` are prohibited.
- `entrypoint.sh` does not loop over profiles. Profile iteration is `scan.py`'s responsibility, exclusively.
- `entrypoint.sh` does not parse YAML. YAML parsing is exclusive to `nuclei_helpers.py`.
- The container does not download `profiles.yaml` at runtime. Profiles are baked into the image at build time.
- `infra/<cloud>/` modules never reference client names or hardcode deployment values. All client-specific configuration comes through variables.
- `deployments/<client>/` calls exactly one `infra/<cloud>/` module (cloud mode only). In local CLI mode, only `targets.txt` is read — all other files in the deployment folder are ignored.
- `infra/gcp/_example/` and `infra/gcp/client-repo-template/` are never deployed from in place. The former is copied into `deployments/<client>/` on this checkout; the latter is copied into a private repo the client owns.
- This public repo's own CI/CD never runs `terraform apply` against a client project, under either topology (see `docs/gcp_architecture.md`). `infra/gcp/client-repo-template/.github/workflows/{deploy,plan}.yml` is a template that becomes the client's own CI once copied to their repo — it is never copied into this repo's `.github/workflows/`.

### Language Policy

- **Python (application runtime):** `scanner/`, `tests/`.
- **Bash (container entrypoint):** `docker/entrypoint.sh`.
- **Terraform (infrastructure):** `infra/`, `deployments/<client>/*.tf`.
- **YAML (config + CI):** `scanner/profiles/profiles.yaml`, `.github/workflows/`, `pyproject.toml` (TOML, but governed by the same dev-tooling pipeline).

Application runtime code is Python. Adding new shell scripts to `scanner/` is prohibited. `docker/entrypoint.sh` remains bash by design — see §2 Runtime Language Policy.

---

## 5. Component Registry

### Local CLI (baseline — build and validate first)

| Component | Source/Domain | Status |
|---|---|---|
| `scanner/scan.py` | Local CLI runner — parses profiles.yaml, invokes Nuclei via subprocess | Complete |
| `scanner/nuclei_helpers.py` | Profile loading, command construction, Nuclei execution | Complete |
| `scanner/nuclei_json_converter.py` | Raw-JSONL → v1 envelope transformation. Hosts `SCHEMA_VERSION`, `build_normalized_document`, `list_executed_profiles`, `consolidate_jsonl_dir` | Complete |
| `scanner/nuclei_convert_tool.py` | Standalone re-consolidation CLI — rebuilds `result-YYYY-MM-DD.json` from existing JSONL without re-scanning | Complete |
| `scanner/upload_to_gcs.py` | Manual GCS push CLI — uploads `results/<client>/<YYYY-MM>/` to GCS bucket. Supports the manual-push workflow in §3 Deployment Modes | Complete |
| `scanner/validate_profiles.py` | Validates every `tags:` entry in `profiles.yaml` against the locally-installed Nuclei template library. Dev/CI tooling | Complete |
| `scanner/profiles/profiles.yaml` | 7 CSFLite-aligned scan profile definitions | Complete |
| `tests/test_nuclei_helpers.py` | Unit tests for helpers module | Complete |
| `tests/test_nuclei_json_converter.py` | Unit tests for the v1 envelope contract | Complete |
| `tests/test_upload_to_gcs.py` | Unit tests for the GCS upload helper | Complete |
| `scanner/_example/targets.txt` | Template target list with placeholder comments | Complete |
| `pyproject.toml`, `poetry.lock` | Python dependency management (Python 3.12, pyyaml, dev tooling) | Complete |
| `.pre-commit-config.yaml` | Black, Ruff, Bandit, pytest pre-commit hooks | Complete |
| `.github/workflows/ci.yaml` | Always-active CI — Black + Ruff + Bandit + pytest | Complete |
| `.gitignore` | Excludes `results/`, `.terraform/`, tfstate, `.venv/` | Complete |
| `README.md` | Three-mode quick start + CSFLite mapping | Complete |

### Local Docker (escalation 1)

| Component | Source/Domain | Status |
|---|---|---|
| `docker/entrypoint.sh` | Container entrypoint — bash wrapper for cloud I/O dispatch; invokes `scan.py` for scan execution | Rebuilt under ADR-007 |
| `docker/Dockerfile.local` | Lightweight image — `python:3.12-slim` base, Nuclei pinned via `NUCLEI_VERSION` build arg, volume mounts; runs `scan.py` inside the image | Rebuilt under ADR-007 |
| `.dockerignore` | Repo-root exclusions for build context (live deployments, results, dev tooling) | Complete |
| `tests/test_container.py` | Docker-gated smoke tests (build, env validation, output parity) | Complete |
| `decisions/ADR-007-python-in-container.md` | Architecture decision: Python carryover into the scanner container | Complete |

### Cloud Automated (escalation 2)

| Component | Source/Domain | Status |
|---|---|---|
| `docker/Dockerfile` | Full image — Nuclei + cloud CLIs (gcloud) | Complete |
| `infra/gcp/` | Terraform module — Cloud Run, Scheduler, GCS, IAM, deployer SA + WIF (`enable_wif`) | Complete |
| `.github/workflows/publish-image.yaml` | CI/CD — build + push scanner image to GHCR on `main`/tag push (public repo, always active) | Complete |
| `infra/gcp/client-repo-template/.github/workflows/{deploy,plan}.yml` | CI/CD template — terraform apply on push to main / plan on PR, WIF-only auth (copied into a private repo the client owns, per ADR-008; never activated in this repo) | Complete |
| `infra/aws/` | Terraform module — ECS Fargate, EventBridge, S3, IAM | Planned |
| `infra/azure/` | Terraform module — Container Apps, Logic Apps, Blob, MI | Planned |
| `infra/gcp/_example/*.tf` | Template Terraform config with placeholders (topology 1) | Complete |
| `infra/gcp/client-repo-template/` | Template client-owned deployment repo, incl. Terraform, workflows, README (topology 2, ADR-008) | Complete |

---

## 6. Scan Profiles

Seven CSFLite-aligned profiles defined in `scanner/profiles/profiles.yaml`:

| Profile | What It Checks | CSFLite Controls |
|---|---|---|
| `baseline_web` | Misconfigs, headers, CORS, TLS, exposed secrets, default creds | PR.AA-01, PR.DS-01, PR.AA-03, PR.IR-01 |
| `patch_cve` | Known CVE checks for common stacks | PR.PS-01 |
| `identity_remote_access` | Default logins, weak auth, exposed admin panels | PR.AA-01, PR.AA-03 |
| `data_protection` | Secrets, .env/.git exposure, public backups | PR.DS-01 |
| `transport_security` | TLS versions/ciphers, HSTS | PR.IR-01 |
| `owasp_top10_core` | OWASP Top 10 baseline sweep | PR.PS-01 |
| `vuln_monitoring` | High/Critical CVE monitoring | PR.PS-01 |

Detailed profile rationale and tuning guidance belong in the Nuclei Configuration Standard (companion document, not yet drafted).

---

## 7. CSFLite Control Mapping

| Control | Weight | Role | Profile(s) |
|---|---|---|---|
| DE.CM-08 | 1.5 | Primary | All — scan execution existence is the evidence |
| PR.AA-01 | 1.5 | Signal | `identity_remote_access`, `baseline_web` |
| PR.DS-01 | 1.2 | Signal | `data_protection`, `baseline_web` |
| PR.PS-01 | 1.0 | Signal | `patch_cve`, `owasp_top10_core`, `vuln_monitoring` |
| PR.IR-01 | 1.0 | Signal | `transport_security`, `baseline_web` |

New profiles must include a `csf_subcategory` mapping in `profiles.yaml`. Control IDs must be valid CSFLite control IDs defined in `csflite/controls.json` (owned by the CSFLite project).

---

## 8. Task Types

### Adding a new client

1. Copy the mode-specific template into `deployments/<client>/` — `scanner/_example/` (Local CLI), `docker/_example/` (Local Docker), or `infra/gcp/_example/` (Cloud/GCP, topology 1)
2. Populate `targets.txt` with the client's external target list
3. If cloud mode: update `terraform.tfvars`, `backend.tf`, `main.tf`
4. Validate: `poetry run python scanner/scan.py <client>` executes without errors

For the client-owned CI topology (ADR-008) instead of topology 1's step 3, see `infra/gcp/client-repo-template/README.md`'s handoff sequence.

### Adding a new scan profile

1. Add profile definition to `scanner/profiles/profiles.yaml` with `csf_subcategory` mapping
2. `scan.py` picks up the new profile automatically — no Python changes required (`load_profiles` iterates the dict)
3. Validate locally: `poetry run python scanner/scan.py <client>`, verify new JSONL file appears in results
4. If container/cloud mode is in use: rebuild the image so the updated `profiles.yaml` is baked in (CI workflow `.github/workflows/publish-image.yaml` triggers automatically on `scanner/profiles/**` changes)

Under ADR-007, the profile-sync surface is gone entirely. `profiles.yaml` is the only place profiles are defined; the container invokes the same `scan.py` the local CLI runs.

### Adding a new cloud vendor

1. Create `infra/<vendor>/` with `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
2. Accept the same required variables as `infra/gcp/`
3. Add the vendor's case block to `docker/entrypoint.sh` (`download_config` and `upload_results`)
4. Add cloud CLI installation to `docker/Dockerfile` if not already present
5. Add a vendor CI/CD workflow template under `infra/<vendor>/`, following the GCP pattern: `_example/` for architect-run topology, a `client-repo-template/` equivalent if the vendor supports client-owned CI. Neither goes in this repo's own `.github/workflows/`.
6. Update `infra/<vendor>/_example/` with a note about the new vendor option

### Modifying scan behavior

1. Change `scanner/profiles/profiles.yaml` — single source of truth
2. `scan.py` picks up the change automatically (local CLI and container both)
3. If container/cloud mode is in use: rebuild the image so the updated `profiles.yaml` is baked in

### Speccing a new component (e.g., web UI)

1. **Do not write code.** Start with the seed document.
2. Add a new section to the seed document covering: what it does, what layer it occupies, what it consumes, what it produces, local mode behavior
3. Define interface contracts — what data formats does it read? What does it expose?
4. Identify design decisions that need to be locked — propose ADRs
5. Only after the architect approves the spec: begin implementation

---

## 9. Acceptance Criteria

### Scanner Layer (local CLI)

1. `poetry install --with dev` completes without errors on a fresh clone
2. `poetry run python scanner/scan.py <client>` executes without errors
3. JSONL files appear in `results/<client>/YYYY-MM/` with at least one non-empty file
4. `jq` can parse every line in every output file
5. `gcloud storage cp` successfully pushes results to the client's GCS bucket
6. Conduit can read the uploaded files (LeanSecurity-side verification)
7. `poetry run pytest` passes
8. `poetry run black --check .`, `poetry run ruff check .`, and `poetry run bandit -r . --severity-level high` all pass

### Client Config (expected structure)

```
# deployments/<client>/targets.txt (used by ALL modes)
https://<client-app-url>

# deployments/<client>/terraform.tfvars (escalation 2 only)
project_id    = "<client-gcp-project-id>"
scanner_image = "<registry>/<project>/<repo>/<image>:latest"

# deployments/<client>/main.tf overrides (escalation 2 only)
region            = "<gcp-region>"
client_name       = "<client-short-name>"
schedule_cron     = "0 2 1-7 * 0"
schedule_timezone = "<client-timezone>"
```

---

## 10. Key Design Decisions — Locked

| Decision | Choice | Rationale |
|---|---|---|
| Scanning tool | Nuclei (ProjectDiscovery) | Open-source, template-based, JSONL output, active community, zero license cost. Standard LeanSecurity VA tool for all engagements. |
| Local CLI as primary mode | Python CLI calls nuclei directly via subprocess — no Docker, no cloud | Fastest path to first scan. Docker and cloud are escalation steps, not prerequisites. |
| Application runtime language | Python 3.12 | Readable, testable, participates in standard CI (Black/Ruff/Bandit/pytest). Replaces the original bash prototype in April 2026. |
| Container entrypoint runtime | Split between bash and Python (see ADR-007) | `docker/entrypoint.sh` is a thin bash wrapper for cloud I/O dispatch; `python /app/scanner/scan.py` runs the scan. The bash layer does not parse YAML and does not loop over profiles. **Supersedes the v1.1 "container entrypoint is bash-only" decision.** |
| Container base image | `python:3.12-slim` with Nuclei binary pinned via `NUCLEI_VERSION` build arg | Matches the planned `vmctl` container's base. Both containers in the repository share the same base for security-update tracking. |
| Progressive deployment | Local CLI → Local Docker → Cloud Automated | Each step adds infrastructure around the same core scan logic. No scan behavior changes between modes. Avoids over-engineering the initial deployment. |
| `scan.py` as standalone scanner | Imports only from `nuclei_helpers`; no Docker awareness, no cloud SDKs, no Terraform | Scanner is the complete scanning capability. Everything in `docker/` and `infra/` is optional infrastructure that can be added or removed without touching the scanner. |
| Runtime YAML parsing in scanner | `nuclei_helpers.load_profiles()` parses `profiles.yaml` at runtime | Single source of truth consumed directly. Adding a profile requires no Python code changes. |
| Profile drift surface eliminated | `entrypoint.sh` does not hardcode any nuclei flags; `scan.py` is invoked directly | Drift between `profiles.yaml` and a parallel hardcoded copy was the v1.1 failure mode. Under ADR-007 the parallel copy does not exist; drift is impossible by construction. |
| `CLOUD_PROVIDER` dispatch | Entrypoint switch on env var (container modes only) | Single entrypoint script serves all clouds. Adding a new provider means adding a case block. |
| Vendor-agnostic scanner layer | `scan.py`, `nuclei_helpers.py`, and `profiles.yaml` have no cloud or container dependencies | Scanner logic is tested and validated independently of deployment target. |
| Per-cloud Terraform modules | One module per cloud vendor under `infra/` | Clean separation. GCP module doesn't know AWS exists. |
| Per-client deployment folders | `deployments/<client>/` with `targets.txt` (all modes) + Terraform files (cloud only) | Version-controlled, auditable. Adding a client is a folder copy. In local mode, only `targets.txt` matters. |
| Ephemeral containers (cloud mode) | Cloud Run job / ECS Fargate / Container Apps | No persistent infrastructure. Pay-per-execution. Container tears down after scan. |
| Cloud storage as Conduit bridge | JSONL pushed to GCS/S3/Blob, Conduit reads from storage | Decoupled — Nuclei doesn't know Conduit exists. Same bridge works for manual push (local) and automatic upload (cloud). |
| `profiles.yaml` as config source of truth | `scan.py` parses at runtime; the container invokes `scan.py`; the local CLI invokes `scan.py` | Single source of truth across all modes. No second copy of the profile flags exists anywhere in the repository. Adding a profile is a one-file change to `profiles.yaml`. |
| Monthly scan cadence (cloud mode) | Cloud Scheduler cron: first Sunday of month, 02:00 client timezone | Aligns with Vulnerability Management Program policy. Off-peak to minimize client app impact. |
| JSONL output format | Nuclei native `-je` flag | No custom formatting. Nuclei's schema is the contract. Conduit adapts to Nuclei. |
| Results date-partitioned | `YYYY-MM/` directories (local filesystem and cloud storage) | Same structure in both modes. `gcloud storage cp` bridges local to cloud with no transformation. |
| Cloud vendor workflows gated | `infra/<vendor>/workflows/` (not auto-active in `.github/workflows/`) | Prevents accidental deploys when no cloud deployment is intended. Activate by manual copy. |
| Railway evaluated and rejected | Does not fit this workload | No object storage, no Terraform provider, no scoped IAM. |

### gcp-cloud-deploy decisions (added 2026-05-28)

The following three decisions were locked as part of the `gcp-cloud-deploy` feature activation. They are appended verbatim from `.claude/docs/project.yaml`.

- "Public-repo, private-deployment topology. The public repository contains the reusable pipeline and module. Per-client deployment configuration lives in client-controlled storage outside the public repository."
- "GHCR is the scanner image distribution channel. The image is built from the public repository and published to ghcr.io/leansecurity/leansec-nuclei. Clients pull from GHCR directly or mirror into their own Artifact Registry."
- "Cloud-side execution is architect-driven, not CI-driven. terraform apply runs from the architect's workstation against the client GCP project. Public-repo CI does not hold GCP credentials and never touches client infrastructure."

---

## 11. What This Project Does Not Own

- **CSFLite control definitions, weights, or scoring methodology** — owned by `LeanSecurity — CSFLite`. Nuclei references control IDs via `profiles.yaml` but never interprets them.
- **Conduit governance platform** — owned by `LeanSecurity — Governance Pipeline`. Nuclei writes JSONL to storage; Conduit reads it. No direct integration.
- **P2 ingest adapter** — owned by `LeanSecurity — Governance Pipeline`. The adapter normalizes Nuclei JSONL to the canonical event model. Nuclei does not know the canonical event model exists.
- **Client vulnerability register** — owned by the client (Excel or Notion). Nuclei produces the JSONL that populates the register; it does not maintain the register.
- **Remediation workflow** — owned by the client IT team. Nuclei identifies vulnerabilities; it does not track or verify remediation.
- **Internal endpoint scanning** — owned by the relevant client project (e.g., Microsoft Defender VMS under Program 1). Nuclei handles external scanning only. The two-engine model is defined in the client's P2 Solution Architecture, not in this project.
- **Client engagement delivery** — owned by the relevant client project. SOWs, invoices, status reports, knowledge transfer sessions are engagement artifacts, not Nuclei project artifacts.
- **Scan profile rationale and operational instructions** — owned by the Nuclei Configuration Standard (companion document, not yet drafted). `profiles.yaml` defines what to scan; the Configuration Standard explains why and how to tune it.

---

## 12. Change Log

| Version | Date | Change |
|---|---|---|
| 1.0 | April 2026 | Initial seed document. Bash scanner (`scan.sh`), bash entrypoint (`entrypoint.sh`), GCP Terraform module, three-mode progressive deployment. |
| 1.1 | April 2026 | Scanner layer ported to Python. `scan.sh` deprecated; `scan.py` + `nuclei_helpers.py` added. `profiles.yaml` now parsed at runtime by `scan.py`. `entrypoint.sh` remains bash (container exception). Python 3.12 + Poetry + CI (Black/Ruff/Bandit/pytest) added. Locked design decisions §10 updated. Profile-sync surface reduced from two scripts to one. |
| 1.2 | May 2026 | ADR-007 integrated. Container layer rebuilt: `python:3.12-slim` base, Nuclei binary at pinned version (`NUCLEI_VERSION` build arg), `scan.py` invoked from a thin bash wrapper. The "container is bash-only" v1.1 decision is reversed. The "drift between profiles.yaml and entrypoint.sh is a bug" v1.1 decision is replaced by structural elimination of the drift surface — `profiles.yaml` is now the single source of truth with no parallel hardcoded copy. `PROFILES_PATH` env var removed; profiles bake into the image. `CLIENT` env var now required at entrypoint. `UPDATE_TEMPLATES` env var added. Profile output stems normalized to canonical names (`identity_remote_access`, `transport_security`, `owasp_top10_core`). |
| 1.3 | May 2026 | Normalized JSON Output wrapped in a versioned envelope (sprint `update/normalize_json_wrapper`). §3 §"Normalized JSON Output" rewritten: the consolidated `result-YYYY-MM-DD.json` is now a single JSON document with `schema_version` (integer; sourced from `nuclei_json_converter.SCHEMA_VERSION = 1`), `scan_run.{client, run_date, profiles_executed, findings_count}`, and `findings[]`. The previous bare-array shape is retired with no backward-compat mode. Finding object shape is unchanged. Envelope construction lives in `scanner/nuclei_json_converter.build_normalized_document(...)`; profile-name derivation from JSONL filenames lives in `list_executed_profiles(...)`. Both `scanner/scan.py` and `scanner/nuclei_convert_tool.py` emit the envelope. Out of scope (deferred): `scan_started_at` / `scan_completed_at` / `scanner_version` fields, consumer-direction schema validation. |
| 1.4 | May 2026 | `gcp-cloud-deploy` feature activated. Public-repo / private-deployments topology locked (three new entries in §10). GCP Terraform module rewritten with `enable_scheduler`, `enable_wif`, `enable_ar_mirror` flags; provider pinned to `google ~> 6.0` (versions.tf added); env blocks on `google_cloud_run_v2_job` rewritten multi-line. Scanner image distribution moved to GHCR (`ghcr.io/leansecurity/leansec-nuclei`) via new `.github/workflows/publish-image.yaml` (three-tag scheme: latest / short-sha / semver). Old `infra/gcp/workflows/{deploy,scanner-image}.yml` removed. Bootstrap script added at `scripts/bootstrap-gcp-client.sh`. `deployments/_example/` refreshed to call the module via a Git source ref. `deployments/mdi/` placeholder removed; `.gitignore` cleaned up. Module reference, architecture distillation, and end-to-end setup guide added under `docs/` and `infra/gcp/`. |
| 1.5 | August 2026 | Client-owned private repo added as a second GCP deployment topology (ADR-008, PR #16–#18): `infra/gcp/client-repo-template/` templates a private repo the client owns, with `deploy.yml`/`plan.yml` running `terraform apply`/`plan` under Workload Identity Federation. Only the operator-facing path (setup guide, skill docs) and one seed-doc sentence were updated at merge time — the architecture doc, root README, CLAUDE.md, and this document's own module tables were not. |
| 1.6 | August 2026 | ADR-008 gap-fix pass (`.claude/tasks/client-repo-topology-gaps.md`). The client-owned topology could not actually run as documented: WIF bound the scanner SA (two bucket bindings) to a workflow needing project-admin Terraform access, and the pinned module `?ref=v1.2.3` never existed as a tag. Fixed: dedicated `deployer` SA with least-privilege separation from the scanner SA (`enable_wif` now provisions it); two-tag release (`v1.1.0` module, `v1.1.1` template) so the pin resolves; `region`/`enable_scheduler`/`enable_ar_mirror`/`schedule_cron`/`schedule_timezone` plumbed as required passthrough variables between the bootstrap module and the client template (previously silently drifted, `enable_ar_mirror` destructively); redundant GCS sync step removed from `deploy.yml`. Full doc reconciliation across `docs/gcp_architecture.md`, root `README.md`, `CLAUDE.md`, this document, `docs/setup-guide.md`, `gcp-deploy` SKILL.md, and ADR-008's own Corrections section. |