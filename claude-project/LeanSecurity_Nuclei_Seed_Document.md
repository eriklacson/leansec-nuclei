# LeanSecurity — Nuclei
## Project Seed Document v1.0
**Classification:** LeanSecurity Internal IP  
**Status:** Architecture decided, Month 1 build in progress  
**Last updated:** April 2026

---

## 1. What This Is

Nuclei is LeanSecurity's standard external vulnerability scanning pipeline. It takes a client's list of public-facing URLs and IPs, runs CSFLite-aligned scan profiles against them using the open-source Nuclei scanner, and produces date-partitioned JSONL output. That output feeds two consumers: the client's vulnerability register (for operational triage and SLA tracking) and LeanSecurity's Conduit governance platform (for automated CSFLite scoring against DE.CM-08).

The baseline operating mode is a local CLI scan run from the consultant's machine — `./scanner/scan.sh <client>` — with results pushed to cloud storage manually when ready for Conduit ingestion. The pipeline can be escalated to containerized and fully automated cloud deployments without changing the scan logic, profiles, or output format.

This is LeanSecurity internal IP. It is not a client deliverable — clients receive scan results and remediation guidance, not the pipeline itself.

The first proof-of-concept deployment is for an active Phase 2 engagement. The client's deployment lives under `deployments/<client>/` in the repository. The client does not own or modify the scanner, infrastructure modules, or CI/CD workflows.

### Project Separation

| Project | Asset Type | Owns |
|---|---|---|
| `LeanSecurity — CSFLite` | Framework IP | Control definitions, weights, scoring methodology. Nuclei consumes `controls.yaml` via the `csf_subcategory` field in profiles.yaml — it does not define or modify controls. |
| `LeanSecurity — [Client]` | Client delivery | Client engagement context, P2 Solution Architecture, Vulnerability Management Program policy, vulnerability register, remediation workflow. Nuclei is one implementation component within P2. |
| `LeanSecurity — Governance Pipeline` | Internal IP | Conduit platform, P2 ingest adapter, canonical event model, CSFLite scoring engine. Conduit consumes Nuclei JSONL output from cloud storage — Nuclei does not write to Conduit directly. |
| `LeanSecurity — Nuclei` | Internal IP | Scanner layer (scan.sh, profiles.yaml), container builds (Dockerfiles, entrypoint.sh), infrastructure modules (Terraform per cloud vendor), client deployment templates, CI/CD workflows, JSONL output format specification. |

---

## 2. Architecture Pattern

**Progressive Deployment Scanner.** A local-first scanning engine that produces identical output across three deployment modes. The baseline is a shell script calling the Nuclei binary directly. Each escalation step (Docker, cloud automation) adds infrastructure around the same core scan logic without modifying it.

### Deployment Modes

| Mode | Dependencies | Execution | Results Storage | Conduit Integration | When to Use |
|---|---|---|---|---|---|
| **Local CLI** (baseline) | Nuclei binary | `./scanner/scan.sh <client>` | Local filesystem: `results/<client>/YYYY-MM/` | Manual `gcloud storage cp` to GCS | Initial engagement scans, proof-of-concept, ad-hoc assessments |
| **Local Docker** (escalation 1) | Docker runtime | `docker run` with volume mounts | Local filesystem via volume mount | Manual `gcloud storage cp` to GCS | Reproducible environment needed, no Nuclei install on host |
| **Cloud Automated** (escalation 2) | Terraform + cloud account | Cloud scheduler triggers ephemeral container | Cloud object storage (GCS/S3/Blob) | Automatic — Conduit reads from bucket | Ongoing monthly automated scans, steady-state operations |

All three modes use the same profiles.yaml, scan the same target list, and produce identical JSONL output. The mode determines how the scan is triggered, where config is read from, and where results are written — not what is scanned or how findings are formatted.

### Layers

**Scanner Layer (local CLI — no dependencies beyond Nuclei)**  
Runs Nuclei CLI against a client target list using 7 CSFLite-aligned profiles. Reads targets from `deployments/<client>/targets.txt`. Writes JSONL to `results/<client>/YYYY-MM/`. This is the complete, functional scanning capability. Everything above this layer is optional infrastructure. Owns: `scanner/scan.sh`, `scanner/profiles/profiles.yaml`. Never touches: Docker, cloud storage, Terraform, Conduit.

**Container Layer (escalation 1 — requires Docker)**  
Wraps the scanner in a Docker image. The entrypoint script dispatches storage download/upload based on a `CLOUD_PROVIDER` environment variable (`local`, `gcp`, `aws`, `azure`). In `local` mode, config and output are volume-mounted — no cloud credentials needed. Owns: `docker/Dockerfile`, `docker/Dockerfile.local`, `docker/entrypoint.sh`. Never touches: Terraform, CI/CD, scan profile definitions.

**Infrastructure Layer (escalation 2 — requires Terraform + cloud account)**  
Provisions cloud resources (compute, storage, scheduler, IAM) via Terraform modules, one per cloud vendor. Each module exposes the same variable interface so client deployments are cloud-portable. Owns: `infra/gcp/`, `infra/aws/`, `infra/azure/`. Never touches: scan logic, Docker builds, profile definitions.

**Deployment Layer (shared across all modes)**  
Per-client configuration: target list and (for cloud mode) Terraform variables and state backend. One folder per client under `deployments/`. In local CLI mode, only `targets.txt` is used. The Terraform files are ignored until the client is escalated to cloud mode. Owns: `targets.txt`, `terraform.tfvars`, `backend.tf`, `main.tf`. Never touches: scanner code, infrastructure module internals, Docker builds.

### Flow — Local CLI (Primary)

```
deployments/<client>/targets.txt
      │
      ▼
 scanner/scan.sh <client>      ← Validates nuclei is installed, targets exist
      │
      ▼
 nuclei CLI × 7 profiles       ← Runs each profile sequentially against target list
      │
      ▼
 results/<client>/YYYY-MM/     ← JSONL files written to local disk
      │
      ▼
 Manual gcloud push (when ready) → GCS bucket → Conduit P2 adapter → DE.CM-08 scoring
```

### Flow — Cloud Automated (Escalation)

```
Cloud Scheduler (monthly cron)
      │
      ▼
 Cloud Run / ECS / Container Apps  ← Ephemeral container spins up
      │
      ▼
 entrypoint.sh                     ← Downloads config from cloud storage
      │
      ▼
 nuclei CLI × 7 profiles           ← Same profiles, same logic as local
      │
      ▼
 Cloud storage upload              ← JSONL pushed to bucket before teardown
      │
      ├──▶ Client vulnerability register  ← Triage, SLA tracking
      └──▶ Conduit P2 ingest adapter      ← CSFLite scoring → DE.CM-08
```

### Delivery Mode

Batch. Each scan run (local or cloud) executes all 7 profiles sequentially, writes results, and exits. No persistent process, no streaming, no event-driven triggers.

**Built and operational now:** Local CLI mode. `scan.sh` runs Nuclei directly on the consultant's host machine.

**Built, not yet deployed:** Local Docker mode (Dockerfile.local + entrypoint.sh). Cloud automated GCP mode (Terraform module + Cloud Run + Cloud Scheduler + GitHub Actions).

**Designed, build deferred:** AWS and Azure Terraform modules (stubbed with READMEs).

---

## 3. Interface Contracts

### scan.sh — Local CLI Interface

The primary interface. Consumed by the operator (consultant). No environment variables, no config files beyond the target list.

| Input/Output | Path | Format | Description |
|---|---|---|---|
| Input: target list | `deployments/<client>/targets.txt` | Plain text, one URL/IP per line, `#` comments | Pre-populated by LeanSecurity per client. |
| Input: profiles | `scanner/profiles/profiles.yaml` | YAML | Reference only — scan.sh hardcodes the Nuclei flags. |
| Output: results | `results/<client>/YYYY-MM/*.jsonl` | JSONL, one file per profile | Date-partitioned by scan month. Gitignored. |
| Output: console | stdout | Text | Progress indicators (`[1/7] baseline_web`) and summary (total findings count). |

**Invocation:**
```
./scanner/scan.sh <client-name>
```

**Exit behavior:** scan.sh uses `|| true` on each Nuclei profile invocation. A profile that finds zero matches exits with code 0 (empty JSONL file). A profile that fails (unreachable target, template error) does not terminate the script — remaining profiles still execute.

### profiles.yaml — Scan Profile Definition

Source of truth for scan configuration. Consumed by `scan.sh` and `docker/entrypoint.sh` as reference — both scripts hardcode the equivalent Nuclei CLI flags to avoid YAML parsing dependencies at runtime.

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
| `profiles.<n>.output` | `string` | Default output filename (overridden at runtime). |
| `profiles.<n>.notes` | `string` | Human-readable description of what the profile checks. |

### JSONL Output — Scan Results

Produced by Nuclei. One JSON object per line per finding. Identical format regardless of deployment mode. Consumed by the client vulnerability register (manual import) and Conduit P2 ingest adapter (automated ingestion from cloud storage).

| Field | Type | Description |
|---|---|---|
| `template-id` | `string` | Nuclei template identifier (e.g., `cve-2024-1234`). Maps to Vulnerability ID in register. |
| `info.name` | `string` | Human-readable vulnerability name. |
| `info.severity` | `string` | `critical` / `high` / `medium` / `low` / `info`. Determines SLA tier. |
| `host` | `string` | Target URL or IP that matched. Maps to Affected Asset in register. |
| `matched-at` | `string` | Specific URL or endpoint matched. Used for remediation targeting. |
| `timestamp` | `string` | ISO 8601 scan timestamp. Maps to Discovery Date in register. |
| `matcher-name` | `string` | Specific condition that triggered the match. Triage detail. |
| `extracted-results` | `list[string]` | Data extracted by the template, if any. Evidence for Conduit. |

### Local Results Directory — Filesystem Contract

Produced by `scan.sh`. Consumed by the operator (manual review, manual push to GCS).

```
results/
└── <client>/
    └── YYYY-MM/
        ├── baseline_web_YYYY-MM.jsonl
        ├── patch_cve_YYYY-MM.jsonl
        ├── identity_YYYY-MM.jsonl
        ├── data_protection_YYYY-MM.jsonl
        ├── transport_YYYY-MM.jsonl
        ├── owasp_top10_YYYY-MM.jsonl
        └── vuln_monitoring_YYYY-MM.jsonl
```

The `results/` directory is gitignored. Scan results are never committed to the repository. The operator decides when and whether to push results to cloud storage for Conduit ingestion.

### Cloud Storage Directory — Bucket Contract

Produced by `docker/entrypoint.sh` (cloud mode) or manual `gcloud storage cp` (local mode). Consumed by Conduit P2 ingest adapter.

```
<results-bucket>/
└── nuclei/
    └── YYYY-MM/
        ├── baseline_web_YYYY-MM.jsonl
        ├── ...
        └── vuln_monitoring_YYYY-MM.jsonl
```

The directory structure mirrors the local results directory. Conduit reads from this path. Lifecycle rules (configurable via Terraform) transition to Nearline at 12 months and delete at 24 months.

### Entrypoint Environment Variables — Container Interface (Escalation 1+2)

Consumed by `docker/entrypoint.sh`. Not used in local CLI mode. Set by docker run `-e` flags (local Docker) or Terraform env blocks (cloud mode).

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `CLOUD_PROVIDER` | `string` | No | `local` | Dispatch target: `local`, `gcp`, `aws`, `azure`. |
| `CONFIG_BUCKET` | `string` | Cloud modes | — | Cloud storage path for config files. |
| `RESULTS_BUCKET` | `string` | Cloud modes | — | Cloud storage path for scan results. |
| `TARGETS_PATH` | `string` | No | `targets/targets.txt` | Path to target list within config bucket. |
| `PROFILES_PATH` | `string` | No | `profiles/profiles.yaml` | Path to profiles.yaml within config bucket. |

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

### Terraform Module Outputs — GCP

| Output | Type | Description |
|---|---|---|
| `config_bucket_name` | `string` | Name of the config storage bucket. |
| `results_bucket_name` | `string` | Name of the results storage bucket. |
| `cloud_run_job_name` | `string` | Name of the Cloud Run job. |
| `scheduler_job_name` | `string` | Name of the scheduler job. |
| `scanner_service_account_email` | `string` | Email of the scanner service account. |

### Design Rules

- profiles.yaml is the source of truth for scan configuration. Both `scan.sh` and `entrypoint.sh` implement the same profiles — if a profile is added or changed in profiles.yaml, both scripts must be updated.
- JSONL output format is defined by Nuclei, not by LeanSecurity. The field mapping above documents the fields we consume — Nuclei may emit additional fields that are ignored.
- The local results directory structure and the cloud storage directory structure are identical. `gcloud storage cp results/<client>/YYYY-MM/*.jsonl gs://<bucket>/nuclei/YYYY-MM/` is the bridge between local and cloud modes — no transformation required.
- Terraform module variable interfaces must be consistent across cloud vendors. `infra/aws/` and `infra/azure/` must accept the same required variables as `infra/gcp/` (with cloud-specific defaults).
- The entrypoint script never hardcodes client names, target URLs, or bucket names. All client-specific values come from environment variables.
- scan.sh never hardcodes client names. The client name is the only argument, and all paths are derived from it.

---

## 4. Component Registry

### Local CLI (baseline — build and validate first)

| Component | Source/Domain | Status |
|---|---|---|
| `scanner/scan.sh` | Local CLI runner — runs Nuclei directly on host | Complete |
| `scanner/profiles/profiles.yaml` | 7 CSFLite-aligned scan profile definitions | Complete |
| `deployments/_example/targets.txt` | Template target list with placeholder comments | Complete |
| `.gitignore` | Excludes results/, .terraform/, tfstate | Complete |
| `README.md` | Three-mode quick start + CSFLite mapping | Complete |

### Local Docker (escalation 1)

| Component | Source/Domain | Status |
|---|---|---|
| `docker/entrypoint.sh` | Container entrypoint with CLOUD_PROVIDER dispatch | Complete |
| `docker/Dockerfile.local` | Lightweight image — Nuclei only, volume mounts | Complete |

### Cloud Automated (escalation 2)

| Component | Source/Domain | Status |
|---|---|---|
| `docker/Dockerfile` | Full image — Nuclei + cloud CLIs (gcloud) | Complete |
| `infra/gcp/` | Terraform module — Cloud Run, Scheduler, GCS, IAM | Complete |
| `infra/aws/` | Terraform module — ECS Fargate, EventBridge, S3, IAM | Planned |
| `infra/azure/` | Terraform module — Container Apps, Logic Apps, Blob, MI | Planned |
| `.github/workflows/scanner-image.yml` | CI/CD — build + push Docker image to Artifact Registry | Complete |
| `.github/workflows/deploy.yml` | CI/CD — terraform plan on PR, apply on merge | Complete |
| `deployments/_example/*.tf` | Template Terraform config with placeholders | Complete |

---

## 5. Repository Structure

### `leansecurity-nuclei`

```
leansecurity-nuclei/
├── scanner/                          ← LOCAL CLI (baseline — no dependencies beyond nuclei)
│   ├── scan.sh                       ← ./scanner/scan.sh <client>
│   └── profiles/
│       └── profiles.yaml             ← Source of truth for scan config
│
├── docker/                           ← ESCALATION 1: container builds
│   ├── Dockerfile                    ← Full image with cloud CLIs (escalation 2)
│   ├── Dockerfile.local              ← Lightweight image, no cloud CLIs (escalation 1)
│   └── entrypoint.sh                 ← CLOUD_PROVIDER dispatch logic
│
├── infra/                            ← ESCALATION 2: Terraform modules
│   ├── gcp/                          ← Implemented
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── aws/                          ← Stubbed (README only)
│   └── azure/                        ← Stubbed (README only)
│
├── deployments/                      ← Per-client config (used by ALL modes)
│   ├── _example/                     ← Template with REPLACE placeholders
│   │   ├── main.tf                   ← Escalation 2 only
│   │   ├── backend.tf                ← Escalation 2 only
│   │   ├── terraform.tfvars          ← Escalation 2 only
│   │   ├── targets.txt               ← Used by ALL modes
│   │   └── README.md
│   └── <client>/                     ← Per-client deployment
│       ├── main.tf                   ← Escalation 2 only
│       ├── backend.tf                ← Escalation 2 only
│       ├── terraform.tfvars          ← Escalation 2 only
│       └── targets.txt               ← Used by ALL modes
│
├── .github/workflows/                ← ESCALATION 2: CI/CD for cloud deployments
│   ├── scanner-image.yml             ← Build + push Docker image
│   └── deploy.yml                    ← Terraform plan/apply per client
│
├── .gitignore                        ← Excludes results/, .terraform/, tfstate
└── README.md                         ← Three-mode quick start + CSFLite mapping
```

### Boundary Rules

- `scanner/` never imports from `docker/` or `infra/`. scan.sh is a standalone script that calls the `nuclei` binary directly. It has no awareness of Docker, containers, cloud storage, or Terraform. This is the complete scanning capability — everything else is optional infrastructure.
- `docker/` never imports from `infra/`. The entrypoint script reads environment variables — it does not know how those variables were set.
- `infra/<cloud>/` modules never reference client names or hardcode deployment values. All client-specific configuration comes through variables.
- `deployments/<client>/` calls exactly one `infra/<cloud>/` module (cloud mode only). In local CLI mode, only `targets.txt` is read — all other files in the deployment folder are ignored.
- `deployments/_example/` is never deployed. The CI/CD workflow excludes directories starting with `_` from the deployment matrix.
- `results/` directory (local CLI output) is gitignored. Scan results are never committed to the repository.

---

## 6. Database Schema

Not applicable. This project is a stateless pipeline. Scan results are files (JSONL), not database records. Persistence is handled by the local filesystem (local CLI/Docker modes) or cloud object storage (cloud mode). The vulnerability register is a client-side artifact (Excel or Notion), not part of this project.

---

## 7. Hosting Stack

### Deployment Profile — Local CLI (Current, Primary)

| Need | Service | Notes |
|------|---------|-------|
| Scan execution | Nuclei binary on consultant's machine | `brew install nuclei` (macOS) or binary download |
| Config storage | Local filesystem (repo) | `deployments/<client>/targets.txt` |
| Results storage | Local filesystem | `results/<client>/YYYY-MM/` |
| Scheduler | Manual | `./scanner/scan.sh <client>` |
| Conduit integration | Manual `gcloud storage cp` | Push JSONL to GCS bucket when ready |

This is the current and primary operating mode. Zero cost, zero cloud dependency, zero Docker dependency. The only prerequisite is the Nuclei binary installed on the consultant's machine.

**Constraint:** The scan host must be outside the client's network for accurate external-perspective results. Running from the consultant's own machine satisfies this by default.

### Deployment Profile — Local Docker (Escalation 1)

| Need | Service | Notes |
|------|---------|-------|
| Scan execution | Docker Desktop / Docker Engine | `docker/Dockerfile.local` — no cloud CLIs |
| Config storage | Volume mount from repo | `-v deployments/<client>/targets.txt:/opt/nuclei/config/targets.txt` |
| Results storage | Volume mount to local filesystem | `-v results/<client>/YYYY-MM:/opt/nuclei/output` |
| Scheduler | Manual | `docker run` |
| Conduit integration | Manual `gcloud storage cp` | Same as local CLI |

Adds reproducible environment (pinned Nuclei version in Docker image) without requiring Nuclei installed on the host. Same manual workflow as local CLI.

### Deployment Profile — GCP Cloud (Escalation 2)

| Need | Service | Notes |
|------|---------|-------|
| Scan execution | Cloud Run job | Ephemeral container, `docker/Dockerfile` (full image) |
| Config storage | GCS bucket | `<client>-nuclei-config` |
| Results storage | GCS bucket | `<client>-security-scans/nuclei/YYYY-MM/` |
| Scheduler | Cloud Scheduler | Monthly cron, configurable timezone |
| Container registry | Artifact Registry | `leansecurity-shared` project |
| CI/CD | GitHub Actions | WIF authentication, terraform plan/apply |
| IAM | GCP service accounts | Separate scanner + scheduler SAs, least privilege |

GCP first because the proof-of-concept client runs their primary application on GCP. Client platform decision for automated deployment is pending negotiation.

### Future Profiles

- **AWS** — ECS Fargate + S3 + EventBridge. Module stubbed at `infra/aws/`.
- **Azure** — Container Apps + Blob Storage + Logic Apps. Module stubbed at `infra/azure/`.
- **Railway** — Evaluated and rejected. No native object storage, no Terraform provider, no scoped IAM. Poor fit for infrastructure automation workloads.

---

## 8. CSFLite Interface Contract

Nuclei does not run the CSFLite scoring engine. It produces evidence that Conduit consumes for scoring. The interface is indirect: profiles.yaml declares which CSFLite controls each profile maps to, and the JSONL output provides the evidence artifacts.

### `profiles.yaml` — CSFLite Mapping

```yaml
profiles:
  baseline_web:
    csf_subcategory: [PR.AA-01, PR.DS-01, PR.AA-03, PR.IR-01]

  patch_cve:
    csf_subcategory: [PR.PS-01]

  identity_remote_access:
    csf_subcategory: [PR.AA-01, PR.AA-03]

  data_protection:
    csf_subcategory: [PR.DS-01]

  transport_security:
    csf_subcategory: [PR.IR-01]

  owasp_top10_core:
    csf_subcategory: [PR.PS-01]

  vuln_monitoring:
    csf_subcategory: [PR.PS-01]
```

### What Conduit's P2 Ingest Adapter Uses

| Field | Used for |
|---|---|
| `csf_subcategory` (from profiles.yaml) | Maps each JSONL finding to one or more CSFLite controls for scoring. |
| `template-id` (from JSONL) | Unique finding identifier for deduplication across scan runs. |
| `info.severity` (from JSONL) | Severity classification for weighted scoring. |
| `timestamp` (from JSONL) | Scan recency — evidence of "scans are performed" (DE.CM-08). |
| `host` (from JSONL) | Asset identification for cross-referencing with the asset inventory. |

The profiles.yaml `csf_subcategory` field uses canonical CSFLite control IDs from `controls.yaml`. Nuclei does not interpret, weight, or score these IDs — it passes them through to Conduit.

### Control Coverage

| Control | Weight | Role | Evidence Source |
|---|---|---|---|
| DE.CM-08 | 1.5 | Primary | Scan execution existence (JSONL files with timestamps). |
| PR.AA-01 | 1.5 | Signal | identity_remote_access profile findings. |
| PR.DS-01 | 1.2 | Signal | data_protection profile findings. |
| PR.PS-01 | 1.0 | Signal | patch_cve + owasp_top10_core + vuln_monitoring findings. |
| PR.IR-01 | 1.0 | Signal | transport_security profile findings. |

---

## 9. Proof-of-Concept — Build Status

### Milestones

| Month | Milestone |
|---|---|
| 1 | Scaffold built. Local CLI mode operational. First scan executed from consultant's machine. Results reviewed and pushed to GCS for Conduit. |
| 2 | Cloud deployment decision made (GCP vs alternatives). If GCP: Terraform apply, Cloud Scheduler live, automated monthly scans. If deferred: continue local CLI with manual monthly runs. |
| 3 | Conduit P2 ingest adapter consuming JSONL from GCS. DE.CM-08 scoring automated. |
| 4-6 | Steady-state operation. Profile tuning based on false positive rates. Target list updates as client deploys new external services. |

### Current Status (Month 1)

**Complete (local CLI baseline):**
- scanner/scan.sh — local CLI runner, validated
- scanner/profiles/profiles.yaml — 7 CSFLite-aligned scan profiles
- deployments/<client>/targets.txt — client external target list
- .gitignore, README.md

**Complete (escalation layers — built, not yet deployed):**
- docker/entrypoint.sh — CLOUD_PROVIDER dispatch (local, gcp, aws, azure)
- docker/Dockerfile — full image with cloud CLIs
- docker/Dockerfile.local — lightweight image
- infra/gcp/ — Terraform module (Cloud Run, Scheduler, GCS, IAM)
- .github/workflows/ — scanner-image.yml, deploy.yml
- deployments/_example/ — template with placeholders
- deployments/<client>/ — Terraform config (main.tf, backend.tf, tfvars)

**In progress:**
- First scan execution against client targets (`./scanner/scan.sh <client>`)
- Client platform decision for automated deployment (GCP vs alternatives)

**Designed, build deferred:**
- AWS and Azure Terraform modules
- Conduit P2 ingest adapter integration
- Nuclei Configuration Standard (client IT team-facing companion document)

### Local CLI Completion Criteria

Local mode is "complete" when:
1. `./scanner/scan.sh <client>` executes without errors
2. JSONL files appear in `results/<client>/YYYY-MM/` with at least one non-empty file
3. `jq` can parse every line in every output file
4. `gcloud storage cp` successfully pushes results to the client's GCS bucket
5. Conduit can read the uploaded files (LeanSecurity-side verification)

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
| Local CLI as primary mode | scan.sh calls nuclei directly, no Docker, no cloud | Zero dependencies beyond the nuclei binary. Fastest path to first scan. Docker and cloud are escalation steps, not prerequisites. |
| Progressive deployment | Local CLI → Local Docker → Cloud Automated | Each step adds infrastructure around the same core scan logic. No scan behavior changes between modes. Avoids over-engineering the initial deployment. |
| scan.sh as standalone script | No YAML parsing, no Docker awareness, no cloud SDK calls | scan.sh is the complete scanning capability. Everything in docker/ and infra/ is optional infrastructure that can be added or removed without touching the scanner. |
| CLOUD_PROVIDER dispatch | Entrypoint switch on env var (container modes only) | Single entrypoint script serves all clouds. Adding a new provider means adding a case block. |
| Vendor-agnostic scanner layer | scan.sh and profiles.yaml have no cloud or container dependencies | Scanner logic is tested and validated independently of deployment target. |
| Per-cloud Terraform modules | One module per cloud vendor under infra/ | Clean separation. GCP module doesn't know AWS exists. |
| Per-client deployment folders | deployments/<client>/ with targets.txt (all modes) + Terraform files (cloud only) | Version-controlled, auditable. Adding a client is a folder copy. In local mode, only targets.txt matters. |
| Ephemeral containers (cloud mode) | Cloud Run job / ECS Fargate / Container Apps | No persistent infrastructure. Pay-per-execution. Container tears down after scan. |
| Cloud storage as Conduit bridge | JSONL pushed to GCS/S3/Blob, Conduit reads from storage | Decoupled — Nuclei doesn't know Conduit exists. Same bridge works for manual push (local) and automatic upload (cloud). |
| profiles.yaml as config source of truth | Profiles defined once, implemented in both scan.sh and entrypoint.sh | Single place to add/modify scan profiles. Both scripts must stay in sync. |
| Monthly scan cadence (cloud mode) | Cloud Scheduler cron: first Sunday of month, 02:00 client timezone | Aligns with Vulnerability Management Program policy. Off-peak to minimize client app impact. |
| JSONL output format | Nuclei native -je flag | No custom formatting. Nuclei's schema is the contract. Conduit adapts to Nuclei. |
| Results date-partitioned | YYYY-MM/ directories (local filesystem and cloud storage) | Same structure in both modes. `gcloud storage cp` bridges local to cloud with no transformation. |
| Railway evaluated and rejected | Does not fit this workload | No object storage, no Terraform provider, no scoped IAM. |

---

## 11. What This Project Does Not Own

- **CSFLite control definitions, weights, or scoring methodology** — owned by `LeanSecurity — CSFLite`. Nuclei references control IDs via profiles.yaml but never interprets them.
- **Conduit governance platform** — owned by `LeanSecurity — Governance Pipeline`. Nuclei writes JSONL to storage; Conduit reads it. No direct integration.
- **P2 ingest adapter** — owned by `LeanSecurity — Governance Pipeline`. The adapter normalizes Nuclei JSONL to the canonical event model. Nuclei does not know the canonical event model exists.
- **Client vulnerability register** — owned by the client (Excel or Notion). Nuclei produces the JSONL that populates the register; it does not maintain the register.
- **Remediation workflow** — owned by the client IT team. Nuclei identifies vulnerabilities; it does not track or verify remediation.
- **Internal endpoint scanning** — owned by the relevant client project (e.g., Microsoft Defender VMS under Program 1). Nuclei handles external scanning only. The two-engine model is defined in the client's P2 Solution Architecture, not in this project.
- **Client engagement delivery** — owned by the relevant client project. SOWs, invoices, status reports, knowledge transfer sessions are engagement artifacts, not Nuclei project artifacts.
- **Scan profile rationale and operational instructions** — owned by the Nuclei Configuration Standard (companion document, not yet drafted). profiles.yaml defines what to scan; the Configuration Standard explains why and how to tune it.
