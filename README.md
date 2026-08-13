# leansec-nuclei

LeanSecurity standard deployment wrapper for Nuclei external vulnerability scanning.

## Overview

Automated Nuclei scans against external assets. Three deployment modes share the same scanner core.

| Mode | What You Need | How It Works |
|------|---------------|--------------|
| **Local CLI** | Nuclei installed | `./scanner/scan.py <client>` — results to local disk |
| **Local Docker** | Docker installed | Build from `docker/Dockerfile.local`, volume-mount config |
| **Cloud (GCP)** | GCP project, Terraform | Cloud Run job + Cloud Scheduler. See [setup guide](docs/setup-guide.md) |

### Operating model — public repo, private deployments

This repository contains the reusable pipeline (scanner core, container, GCP module). **Per-client deployment configuration lives in client-controlled storage outside this repo.** By default, `terraform apply` is run from an architect's workstation against the client GCP project; the public-repo CI never holds GCP credentials and never touches client infrastructure. A second topology exists for clients who want ongoing changes to go through their own CI instead of the architect: a private repo the client owns applies the same Terraform module via Workload Identity Federation. See [ADR-008](decisions/ADR-008-per-client-repo-topology.md) and [`docs/gcp_architecture.md`](docs/gcp_architecture.md) for both.

The scanner image is distributed via GitHub Container Registry: [`ghcr.io/eriklacson/leansec-nuclei`](https://ghcr.io/eriklacson/leansec-nuclei). Production deployments pin to a semver tag.

For the full picture: [`docs/gcp_architecture.md`](docs/gcp_architecture.md) · [module reference](infra/gcp/README.md) · [end-to-end setup guide](docs/setup-guide.md).

## Quick Start (Local CLI)

```bash
# Install Nuclei
brew install nuclei          # macOS
# or: go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Run scan
./scanner/scan.py <client>

# Results in results/<client>/YYYY-MM/
```

### Upload Results to GCS

Push the month's JSONL into a GCS bucket for downstream tooling. In cloud mode, the Cloud Run job uploads automatically. In local mode, push by hand:

```bash
gcloud auth login
gcloud storage cp results/<client>/<YYYY-MM>/*.jsonl \
  gs://<your-bucket>/nuclei/<YYYY-MM>/
```

## Quick Start (Local Docker)

Local Docker is a deployment vehicle for the same `scan.py` the Local CLI runs — output is equivalent at identical paths with identical filenames. Use it when you want to scan without installing Nuclei on the host.

```bash
# Build (build context is repo root, NOT docker/)
docker build -f docker/Dockerfile.local -t eriklacson/leansec-nuclei:local .

# Run a scan
docker run --rm \
  -e CLIENT=<client> \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  eriklacson/leansec-nuclei:local

# Results land in results/<client>/YYYY-MM/ on the host, just like Local CLI.
```

Notes:

- `profiles.yaml` is baked into the image at build time. To change scan profiles, edit `scanner/profiles/profiles.yaml` and rebuild the image.
- The Nuclei version is pinned via `--build-arg NUCLEI_VERSION=vX.Y.Z` (default in `docker/Dockerfile.local`).
- Set `-e UPDATE_TEMPLATES=false` to skip the `nuclei -update-templates` call at startup (useful in air-gapped or CI environments).
- Architecture rationale: see [decisions/ADR-007-python-in-container.md](decisions/ADR-007-python-in-container.md).

### Validating the build against known-vulnerable apps

After rebuilding the scanner image, you can sanity-check it against a
local validation harness (DVWA, Juice Shop, WebGoat). See
[`tests/validation/README.md`](tests/validation/README.md) for the full
workflow. Quick version:

```bash
# Bring up the harness
docker compose -f tests/validation/docker-compose.yaml up -d

# Scan it
docker run --rm \
  --network=scanner-validation \
  -e CLIENT=_validation \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  eriklacson/leansec-nuclei:local

# Tear down
docker compose -f tests/validation/docker-compose.yaml down
```

Expect findings > 0 across multiple profiles. Zero findings against the
validation harness means something is wrong with the rebuild — the apps
are intentionally vulnerable.

## Testing Against DVWA (Local)

Spin up [Damn Vulnerable Web Application](https://github.com/digininja/DVWA) as a known-bad target to validate scan profiles end-to-end:

```bash
# Start DVWA on http://localhost:80
docker run --rm -p 80:80 vulnerables/web-dvwa

# In another terminal, point the localtest deployment at it
echo "http://localhost:80" > deployments/localtest/targets.txt

# Run the scan
./scanner/scan.py localtest

# Inspect findings
ls results/localtest/$(date +%Y-%m)/
```

Expect hits from `baseline_web`, `owasp_top10_core`, and `transport_security` profiles. Use this as smoke-test coverage before promoting profile changes to client deployments.

## Cloud Deployment (GCP)

Cloud-automated deployment runs the scanner as a Cloud Run job on a Cloud Scheduler cadence. By default the pipeline is architect-driven: an architect runs `terraform apply` from their workstation against the client GCP project; after that, Cloud Scheduler triggers the job autonomously. Once provisioned, a client can instead own ongoing Terraform changes from their own private repo's CI ([ADR-008](decisions/ADR-008-per-client-repo-topology.md), [`infra/gcp/client-repo-template/`](infra/gcp/client-repo-template/)) — the sections below cover the architect-driven path.

### Skill-assisted deployment (recommended)

The `/gcp-deploy` Claude Code skill orchestrates the full deployment workflow from a
single high-level `deployment.yaml`. It validates your configuration, renders Terraform
inputs, summarises the plan, and applies with your confirmation — without you having to
touch the Terraform files directly.

**Invoke it** from a Claude Code session in your deployment folder:
- Say "deploy this to GCP" or "set up the scanner on GCP"
- Or run the `/gcp-deploy` slash command

See [`.claude/skills/gcp-deploy/README.md`](.claude/skills/gcp-deploy/README.md) for
prerequisites and a workflow overview, and [`docs/setup-guide.md`](docs/setup-guide.md)
for the full walkthrough.

### Manual deployment (alternative)

```bash
# 1. Bootstrap the client GCP project (one-time)
./scripts/bootstrap-gcp-client.sh <your-project-id>

# 2. Copy the example folder to your private storage
cp -r infra/gcp/_example/ deployments/<client>/

# 3. Edit terraform.tfvars + backend.tf + targets.txt in your copy, then
cd deployments/<client>/
terraform init
terraform plan
terraform apply
```

The scanner image is pulled from GHCR (`ghcr.io/eriklacson/leansec-nuclei`). Production deployments pin to a semver tag. The full walkthrough — including troubleshooting for the common failure modes (API not enabled, IAM denied, image pull failure, etc.) — is in [`docs/setup-guide.md`](docs/setup-guide.md). Maintainers publishing new image versions: see [`docs/release.md`](docs/release.md).

AWS and Azure modules under `infra/aws/` and `infra/azure/` are stubs and not part of the current activation.

## Repository Structure

```
leansecurity-nuclei/
├── scanner/                    # Nuclei CLI runner + profiles (vendor-agnostic)
├── docker/                     # Container build (used by both Local Docker and Cloud modes)
├── infra/gcp/                  # Reusable GCP Terraform module
├── scripts/                    # Operator scripts (bootstrap-gcp-client.sh)
├── scanner/_example/           # Local CLI deployment template
├── docker/_example/            # Local Docker deployment template
├── infra/gcp/_example/         # GCP deployment template (architect-run topology)
├── infra/gcp/client-repo-template/ # GCP deployment template (client-owned CI topology, ADR-008)
├── docs/                       # Architecture + setup guide
├── decisions/                  # Architecture decision records (ADRs)
└── .github/workflows/          # CI (lint/test) + publish-image (GHCR)
```

## CSFLite Control Coverage

| Control | Evidence |
|---------|----------|
| DE.CM-08 | Scan execution + JSONL output |
| PR.AA-01 | identity_remote_access profile |
| PR.DS-01 | data_protection profile |
| PR.PS-01 | patch_cve + owasp_top10_core + vuln_monitoring |
| PR.IR-01 | transport_security profile |
