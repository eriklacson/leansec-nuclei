# leansecurity-nuclei

LeanSecurity standard deployment for Nuclei external vulnerability scanning.

## Overview

Automated Nuclei scans against client external assets. Three deployment modes from simplest to fully automated:

| Mode | What You Need | How It Works |
|------|---------------|--------------|
| **Local CLI** | Nuclei installed | `./scanner/scan.sh mdi` — results to local disk |
| **Local Docker** | Docker installed | Build from `docker/Dockerfile.local`, volume-mount config |
| **Cloud (automated)** | Terraform + GCP/AWS/Azure | Ephemeral containers, cloud scheduler, IaC-managed |

## Quick Start (Local CLI)

```bash
# Install Nuclei
brew install nuclei          # macOS
# or: go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Run scan
./scanner/scan.sh mdi

# Results in results/mdi/YYYY-MM/
```

Push to GCS for Conduit when ready:
```bash
gcloud storage cp results/mdi/2026-04/*.jsonl gs://mdi-security-scans/nuclei/2026-04/
```

## Quick Start (Automated Cloud)

1. Copy `deployments/_example/` to `deployments/<client>/`
2. Update `terraform.tfvars`, `backend.tf`, and `targets.txt`
3. Create the Terraform state bucket (one-time bootstrap)
4. Open a PR → `terraform plan` runs automatically
5. Merge → `terraform apply` provisions all resources

## Repository Structure

```
leansecurity-nuclei/
├── scanner/              # Nuclei CLI runner + profiles (vendor-agnostic)
├── docker/               # Container builds (local Docker + cloud)
├── infra/                # Terraform modules (gcp/ aws/ azure/)
├── deployments/          # Per-client config (_example/ mdi/)
└── .github/workflows/    # CI/CD (image build + terraform deploy)
```

## Documentation

| Document | Audience |
|----------|----------|
| **Local Quickstart** | Erik — run scans now from local machine |
| **Implementation Guide** | Erik / Claude Code — full architecture, IaC, CI/CD |
| **Configuration Standard** | Joepet — profile catalog, rate limiting, schedule |

## CSFLite Controls

| Control | Evidence |
|---------|----------|
| DE.CM-08 | Scan execution + JSONL output |
| PR.AA-01 | identity_remote_access profile |
| PR.DS-01 | data_protection profile |
| PR.PS-01 | patch_cve + owasp_top10_core + vuln_monitoring |
| PR.IR-01 | transport_security profile |
