# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Lean Security — Nuclei Scanner

External vulnerability scanning pipeline using open-source Nuclei against client public-facing assets, producing JSONL output mapped to CSFLite controls.

## Operating Context
- CSFLite is a 25-control governance framework derived from NIST CSF v2.0
- It measures coverage (does this exist?), not maturity or risk
- All outputs must trace to CSFLite controls in `csflite/controls.json`
- Read `csflite/scoring.md` for scoring methodology
- Read `claude-project/LeanSecurity_Nuclei_Seed_Document.md` for project scope and acceptance criteria
- If an `decisions/` directory exists, read it for architecture decisions before planning any work


## Execution Loop
All tasks follow this loop — no exceptions:
1. READ — 'claude-project/LeanSecurity_Nuclei_Seed_Document.md' + 'claud-project/task.md(if exist)'+ controls.json + decisions/(if exist) 
2. PLAN — propose what to build, present to architect for review
3. APPROVE — architect reviews, adjusts, records significant decisions as ADRs
4. IMPLEMENT — build it
5. VERIFY — validate control IDs against controls.json, check acceptance criteria, run tests
6. REPORT — present output + verification results, flag unresolved items honestly

Never skip the PLAN step. Never silently deliver unverified output.
Always validate any task against 'claud-project/task.md(if exist)' + 'claude-project/LeanSecurity_Nuclei_Seed_Document.md' before implementation.



## Architecture

Three deployment modes share the same 7 Nuclei scan profiles:

1. **Local CLI** — `./scanner/scan.sh <client>` runs Nuclei directly on the host, reads `deployments/<client>/targets.txt`, writes JSONL to `results/<client>/YYYY-MM/`
2. **Local Docker** — `docker/Dockerfile.local` with volume mounts for config and results
3. **Cloud (GCP)** — Terraform-managed Cloud Run job + Cloud Scheduler, ephemeral container on cron schedule

### Scan Profiles (`scanner/profiles/profiles.yaml`)

Source of truth for all scan configuration. Seven CSFLite-aligned profiles:

| Profile | CSFLite Controls | Rate |
|---|---|---|
| baseline_web | PR.AA-01, PR.DS-01, PR.AA-03, PR.IR-01 | 3 req/s |
| patch_cve | PR.PS-01 | 3 req/s |
| identity_remote_access | PR.AA-01, PR.AA-03 | 3 req/s |
| data_protection | PR.DS-01 | 3 req/s |
| transport_security | PR.IR-01 | 3 req/s |
| owasp_top10_core | PR.PS-01 | 10 req/s, concurrency=50 |
| vuln_monitoring | PR.PS-01 | 3 req/s |

`scan.sh` and `docker/entrypoint.sh` both hardcode the same Nuclei flags to avoid YAML parsing at runtime.

### Client Deployments (`deployments/`)

Each subdirectory (except `_example/`) is an active client. CI auto-discovers these — adding a new folder to `deployments/` automatically triggers Terraform plan/apply in CI. Copy `deployments/_example/` as the template for new clients.

### Infrastructure (`infra/`)

- **GCP** (`infra/gcp/`): Production-ready. Creates Cloud Run job, Cloud Scheduler, two GCS buckets (config + results), IAM service accounts.
- **AWS/Azure** (`infra/aws/`, `infra/azure/`): Stubbed — variables match GCP interface but resources are not implemented.

## Commands

```bash
# Install Python dependencies
poetry install --with dev

# Lint and format checks
poetry run black --check .
poetry run ruff check .
poetry run bandit -r . -x ".venv,venv,build,dist,docs,migrations,tests"

# Tests
poetry run python -m pytest -q --maxfail=1 --disable-warnings

# Run a scan locally (requires Nuclei installed)
./scanner/scan.py <client>

# Build Docker image (local)
docker build -f docker/Dockerfile.local -t nuclei-scanner .

# Terraform (per client)
cd deployments/<client>
terraform init
terraform plan
terraform apply
```

## CI/CD

- `.github/workflows/ci.yaml`: Black + Ruff + Bandit + pytest on every push/PR to main — always active
- `infra/gcp/workflows/scanner-image.yml`: Builds and pushes Docker image to GCP Artifact Registry when `docker/` or `scanner/profiles/` changes
- `infra/gcp/workflows/deploy.yml`: Terraform plan on PR, apply on merge, auto-discovered per client in `deployments/`

Cloud vendor workflows live under `infra/<vendor>/workflows/` and must be manually copied to `.github/workflows/` to activate. This prevents accidental deploys when no cloud deployment is intended.

## Stack Conventions
- Python: Poetry (tooling only — no Python source code currently)
- Shell: Bash (scanner, entrypoint)
- IaC: Terraform (GCP production, AWS/Azure stubbed)
- Data: JSON for machine-readable, YAML for human-editable

## Hard Prohibitions
- No maturity scoring — coverage only
- No compliance certification claims — CSFLite is not a compliance framework
- No tool accumulation — governance clarity over tool sprawl
- No speculative scope expansion — build what the spec says
- Never push to remote — architect controls what leaves the repo
