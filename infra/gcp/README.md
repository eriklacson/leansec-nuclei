# GCP Infrastructure Module

Provisions all GCP resources for automated Nuclei scanning.

## Required APIs

Enable in the client GCP project:

- Cloud Run Admin API (`run.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Artifact Registry API (`artifactregistry.googleapis.com`)

## Usage

```hcl
module "nuclei" {
  source = "../../infra/gcp"

  project_id    = "client-gcp-project-id"
  region        = "asia-southeast1"
  client_name   = "clientname"
  scanner_image = "asia-southeast1-docker.pkg.dev/leansecurity-shared/nuclei/scanner:latest"
  targets_file  = "${path.module}/targets.txt"
}
```

See `deployments/_example/` for a complete template.
