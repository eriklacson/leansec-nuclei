# leansecurity-nuclei

LeanSecurity standard deployment for Nuclei external vulnerability scanning.

## Overview

Automated Nuclei scans against client external assets. Currently supports local execution; cloud-automated deployment is planned for the next phase.

| Mode | What You Need | How It Works |
|------|---------------|--------------|
| **Local CLI** | Nuclei installed | `./scanner/scan.py <client>` — results to local disk |
| **Local Docker** | Docker installed | Build from `docker/Dockerfile.local`, volume-mount config |
| **Cloud (automated)** | _Next phase_ | Terraform + Cloud Run/Scheduler — not yet available |

## Quick Start (Local CLI)

```bash
# Install Nuclei
brew install nuclei          # macOS
# or: go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Run scan
./scanner/scan.py <client>

# Results in results/<client>/YYYY-MM/
```

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

## Cloud Deployment — Next Phase

Cloud-automated deployment (Terraform + Cloud Run job + Cloud Scheduler, ephemeral containers, IaC-managed per client) is planned for the next phase and is **not yet available**. Scaffolding under `infra/` and `infra/<vendor>/workflows/` is staged for that work but inactive — do not attempt to provision from `main` yet.

## Repository Structure

```
leansecurity-nuclei/
├── scanner/                    # Nuclei CLI runner + profiles (vendor-agnostic)
├── docker/                     # Container builds (local Docker today; cloud next phase)
├── deployments/                # Per-client config (see _example/)
└── .github/workflows/          # Active CI/CD (ci.yaml — lint/test only)
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
