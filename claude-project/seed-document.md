# LeanSecurity — Nuclei
## Project Seed Document v1.0
**Classification:** LeanSecurity Internal IP  
**Status:** Architecture decided, Month 1 build in progress  
**Last updated:** April 2026

---

## 1. What This Is

Nuclei is LeanSecurity's standard external vulnerability scanning pipeline. It takes a client's list of public-facing URLs and IPs, runs CSFLite-aligned scan profiles against them using the open-source Nuclei scanner, and produces date-partitioned JSONL output. That output feeds two consumers: the client's vulnerability register (for operational triage and SLA tracking) and LeanSecurity's Conduit governance platform (for automated CSFLite scoring against DE.CM-08). The pipeline supports three deployment modes — local CLI, local Docker, and cloud-automated — all producing identical output.

This is LeanSecurity internal IP. It is not a client deliverable — clients receive scan results and remediation guidance, not the pipeline itself.

Macro Distributors Inc. (MDI) is the proof-of-concept client. MDI's deployment lives under `deployments/mdi/` in the repository. MDI does not own or modify the scanner, infrastructure modules, or CI/CD workflows.

### Project Separation

| Project | Asset Type | Owns |
|---|---|---|
| `LeanSecurity — CSFLite` | Framework IP | Control definitions, weights, scoring methodology. Nuclei consumes `controls.yaml` via the `csf_subcategory` field in profiles.yaml — it does not define or modify controls. |
| `LeanSecurity — MDI` | Client delivery | MDI engagement context, P2 Solution Architecture, Vulnerability Management Program policy, vulnerability register, remediation workflow. Nuclei is one implementation component within P2. |
| `LeanSecurity — Governance Pipeline` | Internal IP | Conduit platform, P2 ingest adapter, canonical event model, CSFLite scoring engine. Conduit consumes Nuclei JSONL output from cloud storage — Nuclei does not write to Conduit directly. |
| `LeanSecurity — Nuclei` | Internal IP | Scanner layer (scan.sh, profiles.yaml), container builds (Dockerfiles, entrypoint.sh), infrastructure modules (Terraform per cloud vendor), client deployment templates, CI/CD workflows, JSONL output format specification. |

---

## 2. Architecture Pattern

**Multi-Mode Scanner with Vendor-Agnostic Core.** A shared scanning engine (Nuclei CLI + CSFLite-aligned profiles) wrapped in progressively more automated deployment modes. The core scan logic is identical across all modes; only the execution environment and storage integration vary.

### Layers

**Scanner Layer**  
Runs Nuclei CLI against a client target list using 7 CSFLite-aligned profiles. Produces JSONL output. This layer has zero cloud or container dependencies — it runs anywhere Nuclei is installed. Owns: `scan.sh`, `profiles.yaml`. Never touches: cloud storage, container orchestration, Terraform, Conduit.

**Container Layer**  
Wraps the scanner in a Docker image with cloud CLI tooling. The entrypoint script dispatches storage download/upload based on a `CLOUD_PROVIDER` environment variable. Supports `local`, `gcp`, `aws`, and `azure` modes. Owns: `Dockerfile`, `Dockerfile.local`, `entrypoint.sh`. Never touches: Terraform, CI/CD, scan profile definitions.

**Infrastructure Layer**  
Provisions cloud resources (compute, storage, scheduler, IAM) via Terraform modules, one per cloud vendor. Each module exposes the same variable interface so client deployments are cloud-portable. Owns: `infra/gcp/`, `infra/aws/`, `infra/azure/`. Never touches: scan logic, Docker builds, profile definitions.

**Deployment Layer**  
Per-client configuration: target list, Terraform variables, state backend. One folder per client under `deployments/`. Owns: `targets.txt`, `terraform.tfvars`, `backend.tf`, `main.tf`. Never touches: scanner code, infrastructure module internals, Docker builds.

### Flow

```
targets.txt (per client)
      │
      ▼
 scan.sh / entrypoint.sh    ← Runs 7 Nuclei profiles against target list
      │
      ▼
 JSONL output files          ← One file per profile, date-partitioned (YYYY-MM)
      │
      ├──▶ Local disk (local CLI mode)
      │         │
      │         ▼
      │    Manual gcloud push ← Operator pushes to GCS when ready
      │
      └──▶ Cloud storage (cloud mode)
                │
                ├──▶ Client vulnerability register  ← Triage, SLA tracking, remediation
                │
                └──▶ Conduit P2 ingest adapter       ← Normalize → CSFLite scoring → DE.CM-08
```

### Delivery Mode

Batch. Each scan run executes all 7 profiles sequentially, writes results, and exits. No persistent process, no streaming, no event-driven triggers.

**Built now:** Local CLI mode (scan.sh running Nuclei directly on host). Manual push to GCS.

**Designed, build deferred:** Local Docker mode (Dockerfile.local + entrypoint.sh). Cloud automated mode (Terraform + Cloud Run + Cloud Scheduler + GitHub Actions CI/CD). GCP module is written; AWS and Azure modules are stubbed.

---

## 3. Interface Contracts

### profiles.yaml — Scan Profile Definition

Defines CSFLite-aligned scan profiles. Consumed by `scan.sh` (as documentation/reference) and `entrypoint.sh` (as documentation/reference). The actual Nuclei CLI flags are hardcoded in both scripts to avoid YAML parsing dependencies at runtime.

| Field | Type | Description |
|---|---|---|
| `version` | `int` | Schema version. Currently `1`. |
| `profiles.<name>.tags` | `list[string]` | Nuclei template tags to include. |
| `profiles.<name>.severity` | `list[string]` | Severity filter: `info`, `low`, `medium`, `high`, `critical`. |
| `profiles.<name>.csf_subcategory` | `list[string]` | CSFLite control IDs this profile provides evidence for. |
| `profiles.<name>.rate_limit` | `int` | Max requests per second. |
| `profiles.<name>.concurrency` | `int` | Max concurrent template executions. |
| `profiles.<name>.retries` | `int` | Retry count per template. |
| `profiles.<name>.timeout` | `int` | Per-request timeout in seconds. |
| `profiles.<name>.input_mode` | `string` | Nuclei input mode: `list` or `single`. |
| `profiles.<name>.output` | `string` | Default output filename (overridden at runtime). |
| `profiles.<name>.notes` | `string` | Human-readable description of what the profile checks. |

### JSONL Output — Scan Results

Produced by Nuclei. One JSON object per line per finding. Consumed by the client vulnerability register (manual import) and Conduit P2 ingest adapter (automated ingestion from cloud storage).

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

### Entrypoint Environment Variables — Container Interface

Consumed by `docker/entrypoint.sh`. Set by the infrastructure layer (Terraform env blocks for cloud mode, `-e` flags for local Docker mode).

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `CLOUD_PROVIDER` | `string` | No | `local` | Dispatch target: `local`, `gcp`, `aws`, `azure`. |
| `CONFIG_BUCKET` | `string` | Cloud modes | — | Cloud storage path for config files. |
| `RESULTS_BUCKET` | `string` | Cloud modes | — | Cloud storage path for scan results. |
| `TARGETS_PATH` | `string` | No | `targets/targets.txt` | Path to target list within config bucket. |
| `PROFILES_PATH` | `string` | No | `profiles/profiles.yaml` | Path to profiles.yaml within config bucket. |

### Terraform Module Variables — GCP

Consumed by client deployment `main.tf`. Produced by `infra/gcp/variables.tf`.

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `project_id` | `string` | Yes | — | Client GCP project ID. |
| `region` | `string` | No | `asia-southeast1` | GCP region for all resources. |
| `client_name` | `string` | Yes | — | Short client identifier (e.g., `mdi`). |
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
- Terraform module variable interfaces must be consistent across cloud vendors. `infra/aws/` and `infra/azure/` must accept the same required variables as `infra/gcp/` (with cloud-specific defaults).
- The entrypoint script never hardcodes client names, target URLs, or bucket names. All client-specific values come from environment variables set by the infrastructure layer.

---

## 4. Component Registry

| Component | Source/Domain | Status |
|---|---|---|
| `scanner/scan.sh` | Local CLI runner — runs Nuclei directly on host | Complete |
| `scanner/profiles/profiles.yaml` | 7 CSFLite-aligned scan profile definitions | Complete |
| `docker/entrypoint.sh` | Container entrypoint with CLOUD_PROVIDER dispatch | Complete |
| `docker/Dockerfile` | Full image — Nuclei + cloud CLIs (gcloud) | Complete |
| `docker/Dockerfile.local` | Lightweight image — Nuclei only, volume mounts | Complete |
| `infra/gcp/` | Terraform module — Cloud Run, Scheduler, GCS, IAM | Complete |
| `infra/aws/` | Terraform module — ECS Fargate, EventBridge, S3, IAM | Planned |
| `infra/azure/` | Terraform module — Container Apps, Logic Apps, Blob, MI | Planned |
| `.github/workflows/scanner-image.yml` | CI/CD — build + push Docker image to Artifact Registry | Complete |
| `.github/workflows/deploy.yml` | CI/CD — terraform plan on PR, apply on merge | Complete |
| `deployments/_example/` | Template client deployment with placeholder values | Complete |
| `deployments/mdi/` | MDI client deployment — targets, tfvars, backend | Complete |

---

## 5. Repository Structure

### `leansecurity-nuclei`

```
leansecurity-nuclei/
├── scanner/                          ← Local CLI runner + shared profiles
│   ├── scan.sh                       ← ./scanner/scan.sh <client>
│   └── profiles/
│       └── profiles.yaml             ← Source of truth for scan config
│
├── docker/                           ← Container builds (local Docker + cloud)
│   ├── Dockerfile                    ← Full image with cloud CLIs
│   ├── Dockerfile.local              ← Lightweight image, no cloud CLIs
│   └── entrypoint.sh                 ← CLOUD_PROVIDER dispatch logic
│
├── infra/                            ← Vendor-specific Terraform modules
│   ├── gcp/                          ← Implemented
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── aws/                          ← Stubbed (README only)
│   └── azure/                        ← Stubbed (README only)
│
├── deployments/                      ← Per-client instantiations
│   ├── _example/                     ← Template with REPLACE placeholders
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   ├── terraform.tfvars
│   │   ├── targets.txt
│   │   └── README.md
│   └── mdi/                          ← MDI proof-of-concept deployment
│       ├── main.tf
│       ├── backend.tf
│       ├── terraform.tfvars
│       └── targets.txt
│
├── .github/workflows/                ← CI/CD for cloud deployments
│   ├── scanner-image.yml             ← Build + push Docker image
│   └── deploy.yml                    ← Terraform plan/apply per client
│
├── .gitignore                        ← Excludes results/, .terraform/, tfstate
└── README.md                         ← Three-mode quick start + CSFLite mapping
```

### Boundary Rules

- `scanner/` never imports from `docker/`. scan.sh is a standalone script that calls the `nuclei` binary directly. It has no awareness of Docker, containers, or cloud storage.
- `docker/` never imports from `infra/`. The entrypoint script reads environment variables — it does not know how those variables were set (Terraform, docker run -e, Kubernetes manifest).
- `infra/<cloud>/` modules never reference client names or hardcode deployment values. All client-specific configuration comes through variables.
- `deployments/<client>/` calls exactly one `infra/<cloud>/` module. A client deployment never calls multiple cloud modules or reference other clients.
- `deployments/_example/` is never deployed. The CI/CD workflow excludes directories starting with `_` from the deployment matrix.
- `results/` directory (local CLI output) is gitignored. Scan results are never committed to the repository.

---

## 6. Database Schema

Not applicable. This project is a stateless pipeline. Scan results are files (JSONL), not database records. Persistence is handled by the filesystem (local mode) or cloud object storage (cloud mode). The vulnerability register is a client-side artifact (Excel or Notion), not part of this project.

---

## 7. Hosting Stack

### Infrastructure Needs

| Need | Interface/Constraint | Notes |
|------|---------------------|-------|
| Scan execution | Nuclei CLI binary (Go) or Docker runtime | Local: bare binary. Cloud: container image. |
| Config storage | Filesystem or S3-compatible object store | Holds targets.txt and profiles.yaml per client. |
| Results storage | Filesystem or S3-compatible object store | Holds date-partitioned JSONL output. Must be readable by Conduit. |
| Scheduler | Cron (local) or cloud-native scheduler | Monthly cadence. Ad-hoc runs supported. |
| Container registry | OCI-compatible registry | Only needed for Docker/cloud modes. |
| CI/CD | GitHub Actions | Only needed for cloud mode. |

### Deployment Profile — Local CLI (Current)

| Need | Service | Notes |
|------|---------|-------|
| Scan execution | Nuclei binary on Erik's machine | `brew install nuclei` |
| Config storage | Local filesystem (repo) | `deployments/<client>/targets.txt` |
| Results storage | Local filesystem | `results/<client>/YYYY-MM/` |
| Scheduler | Manual | `./scanner/scan.sh mdi` |
| Conduit integration | Manual `gcloud storage cp` | Push JSONL to GCS when ready |

This is the current operating mode. Zero cost, zero cloud dependency. Suitable for initial engagement scans and proof-of-concept validation.

### Deployment Profile — GCP Cloud (Target)

| Need | Service | Notes |
|------|---------|-------|
| Scan execution | Cloud Run job | Ephemeral container, projectdiscovery/nuclei base image |
| Config storage | GCS bucket | `<client>-nuclei-config` |
| Results storage | GCS bucket | `<client>-security-scans/nuclei/YYYY-MM/` |
| Scheduler | Cloud Scheduler | Monthly cron, Asia/Manila timezone (MDI) |
| Container registry | Artifact Registry | `leansecurity-shared` project |
| CI/CD | GitHub Actions | WIF authentication, terraform plan/apply |
| IAM | GCP service accounts | Separate scanner + scheduler SAs, least privilege |

GCP first because MDI (proof-of-concept client) runs their BI application on GCP. Client platform decision for automated deployment is pending negotiation.

### Future Profiles

- **AWS** — ECS Fargate + S3 + EventBridge. Module stubbed at `infra/aws/`.
- **Azure** — Container Apps + Blob Storage + Logic Apps. Module stubbed at `infra/azure/`.
- **Railway** — Evaluated and deferred. No native object storage, no Terraform provider, no scoped IAM. Poor fit for infrastructure automation workloads.

---

## 8. CSFLite Interface Contract

Nuclei does not run the CSFLite scoring engine. It produces evidence that Conduit consumes for scoring. The interface is indirect: profiles.yaml declares which CSFLite controls each profile maps to, and the JSONL output provides the evidence artifacts.

### `profiles.yaml` — CSFLite Mapping

```yaml
profiles:
  baseline_web:
    csf_subcategory: [PR.AA-01, PR.DS-01, PR.AA-03, PR.IR-01]
    # ...scan config...

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
| DE.CM-08 | 1.5 | Primary | Scan execution existence (JSONL files in storage with timestamps). |
| PR.AA-01 | 1.5 | Signal | identity_remote_access profile findings. |
| PR.DS-01 | 1.2 | Signal | data_protection profile findings. |
| PR.PS-01 | 1.0 | Signal | patch_cve + owasp_top10_core + vuln_monitoring findings. |
| PR.IR-01 | 1.0 | Signal | transport_security profile findings. |

---

## 9. Proof-of-Concept — Build Status

### MDI — Milestones

| Month | Milestone |
|---|---|
| 1 | Scaffold built. Local CLI mode operational. First scan executed from Erik's machine. Results pushed to GCS manually. |
| 2 | Cloud deployment decision made (GCP vs Railway vs other). If GCP: Terraform apply, Cloud Scheduler live, automated monthly scans. |
| 3 | Conduit P2 ingest adapter consuming JSONL from GCS. DE.CM-08 scoring automated. |
| 4-6 | Steady-state operation. Profile tuning based on false positive rates. Target list updates as MDI deploys new external services. |

### Current Status (Month 1)

**Complete:**
- Scaffold built (24 files across scanner, docker, infra, deployments, CI/CD)
- profiles.yaml with 7 CSFLite-aligned scan profiles
- scan.sh local CLI runner
- Docker entrypoint with CLOUD_PROVIDER dispatch (local, gcp, aws, azure)
- GCP Terraform module (Cloud Run, Scheduler, GCS, IAM)
- GitHub Actions workflows (scanner-image.yml, deploy.yml)
- MDI deployment folder (targets.txt, tfvars, backend.tf)
- Implementation Guide and Local Quickstart documents

**In progress:**
- First scan execution against MDI targets (pending `./scanner/scan.sh mdi` run)
- Client platform decision for automated deployment (GCP vs alternatives)

**Designed, build deferred:**
- AWS and Azure Terraform modules
- Conduit P2 ingest adapter integration
- Nuclei Configuration Standard (Joepet-facing companion document)

### Client Config (MDI deployment)

```yaml
# deployments/mdi/terraform.tfvars
project_id:    "mdi-gcp-project-id"
scanner_image: "asia-southeast1-docker.pkg.dev/leansecurity-shared/nuclei/scanner:latest"

# deployments/mdi/main.tf overrides
region:            "asia-southeast1"
client_name:       "mdi"
schedule_cron:     "0 2 1-7 * 0"    # First Sunday of month, 02:00
schedule_timezone: "Asia/Manila"

# deployments/mdi/targets.txt
# https://bi.macrodistributors.com
```

---

## 10. Key Design Decisions — Locked

| Decision | Choice | Rationale |
|---|---|---|
| Scanning tool | Nuclei (ProjectDiscovery) | Open-source, template-based, JSONL output, active community, zero license cost. Standard LeanSecurity VA tool for all engagements. |
| Local CLI as baseline | scan.sh calls nuclei directly, no Docker | Zero dependencies beyond the nuclei binary. Fastest path to first scan. Docker is an escalation, not a prerequisite. |
| CLOUD_PROVIDER dispatch | Entrypoint switch on env var | Single entrypoint script serves all clouds. Adding a new provider means adding a case block, not a new entrypoint. |
| Vendor-agnostic scanner layer | scan.sh and profiles.yaml have no cloud dependencies | Scanner logic is tested and validated independently of deployment target. Same profiles, same output, regardless of where it runs. |
| Per-cloud Terraform modules | One module per cloud vendor under infra/ | Clean separation. GCP module doesn't know AWS exists. Client deployments pick exactly one. |
| Per-client deployment folders | deployments/<client>/ with targets + tfvars | Version-controlled, CI/CD-deployed, auditable. Adding a client is a folder copy, not a code change. |
| Ephemeral containers (cloud mode) | Cloud Run job / ECS Fargate / Container Apps | No persistent infrastructure. Pay-per-execution. Container tears down after scan. |
| GCS as Conduit integration point | JSONL pushed to GCS bucket, Conduit reads from GCS | Decoupled — Nuclei doesn't know Conduit exists. Conduit doesn't know where Nuclei ran. GCS is the contract boundary. |
| profiles.yaml as config source of truth | Profiles defined once, referenced by both scan.sh and entrypoint.sh | Single place to add/modify scan profiles. Both scripts implement the same profile set. |
| Monthly scan cadence | Cloud Scheduler cron: first Sunday of month, 02:00 client timezone | Aligns with Vulnerability Management Program policy (monthly for Critical assets). Off-peak to minimize BI app impact. |
| JSONL output format | Nuclei native -je flag | No custom output formatting. Nuclei's JSONL schema is the contract. Conduit adapts to Nuclei, not the other way around. |
| Results date-partitioned | YYYY-MM/ directories in storage | Simple, predictable structure. One month = one folder. Lifecycle policies apply cleanly. |
| Railway evaluated and rejected | Does not fit this workload | No object storage, no Terraform provider, no scoped IAM. Good for web apps, poor for infrastructure automation jobs. |

---

## 11. What This Project Does Not Own

- **CSFLite control definitions, weights, or scoring methodology** — owned by `LeanSecurity — CSFLite`. Nuclei references control IDs via profiles.yaml but never interprets them.
- **Conduit governance platform** — owned by `LeanSecurity — Governance Pipeline`. Nuclei writes JSONL to storage; Conduit reads it. No direct integration.
- **P2 ingest adapter** — owned by `LeanSecurity — Governance Pipeline`. The adapter normalizes Nuclei JSONL to the canonical event model. Nuclei does not know the canonical event model exists.
- **Client vulnerability register** — owned by the client (Excel or Notion). Nuclei produces the JSONL that populates the register; it does not maintain the register.
- **Remediation workflow** — owned by the client IT team. Nuclei identifies vulnerabilities; it does not track or verify remediation.
- **Microsoft Defender VMS (internal scanning)** — owned by `LeanSecurity — MDI` (Program 1). Nuclei handles external scanning only. The two-engine model is defined in the client's P2 Solution Architecture, not in this project.
- **Client engagement delivery** — owned by `LeanSecurity — MDI` (or the relevant client project). SOWs, invoices, status reports, knowledge transfer sessions are engagement artifacts, not Nuclei project artifacts.
- **Scan profile rationale and operational instructions** — owned by the Nuclei Configuration Standard (companion document, not yet drafted). profiles.yaml defines what to scan; the Configuration Standard explains why and how to tune it.