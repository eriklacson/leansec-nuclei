# leansecurity-nuclei

LeanSecurity standard deployment for Nuclei external vulnerability scanning.

## Overview

Automated Nuclei scans against client external assets. Three deployment modes from simplest to fully automated:

| Mode | What You Need | How It Works |
|------|---------------|--------------|
| **Local CLI** | Nuclei installed | `./scanner/scan.py mdi` — results to local disk |
| **Local Docker** | Docker installed | Build from `docker/Dockerfile.local`, volume-mount config |
| **Cloud (automated)** | Terraform + GCP/AWS/Azure | Ephemeral containers, cloud scheduler, IaC-managed |

## Quick Start (Local CLI)

```bash
# Install Nuclei
brew install nuclei          # macOS
# or: go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Run scan
./scanner/scan.py mdi

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
4. Copy the vendor workflows into `.github/workflows/` to activate CI/CD:
   ```bash
   cp infra/gcp/workflows/*.yml .github/workflows/
   ```
5. Open a PR → `terraform plan` runs automatically
6. Merge → `terraform apply` provisions all resources

> Cloud vendor workflows live in `infra/<vendor>/workflows/` and are **not active by default**. Copy them to `.github/workflows/` only when a cloud deployment is intended. This prevents accidental deploys on every push to main.

## Repository Structure

```
leansecurity-nuclei/
├── scanner/                    # Nuclei CLI runner + profiles (vendor-agnostic)
├── docker/                     # Container builds (local Docker + cloud)
├── infra/                      # Terraform modules per vendor
│   └── gcp/
│       ├── workflows/          # Inactive CI/CD workflows (deploy when ready)
│       └── *.tf                # GCP Cloud Run + Scheduler + GCS
├── deployments/                # Per-client config (_example/ mdi/)
└── .github/workflows/          # Active CI/CD (ci.yaml always; vendor workflows on demand)
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
