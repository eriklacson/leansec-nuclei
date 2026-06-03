# GCP Infrastructure Module

Provisions a Cloud Run job, optional Cloud Scheduler trigger, two GCS
buckets (config + results), service accounts, IAM bindings, and optional
Workload Identity Federation and Artifact Registry mirror for the
LeanSecurity Nuclei scanner pipeline.

The module is consumed from a per-client deployment folder
(`deployments/_example/` is the template). Architects run `terraform
apply` from their workstation against the client GCP project; the public
repository does not hold cloud credentials.

## Prerequisites

1. **gcloud authenticated** — `gcloud auth login` and `gcloud auth application-default login`.
2. **IAM** — your principal needs the roles listed by [`scripts/bootstrap-gcp-client.sh`](../../scripts/bootstrap-gcp-client.sh): `roles/run.admin`, `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountUser`, `roles/storage.admin`, plus conditional roles for the optional flags. The client admin grants these on the target project.
3. **Bootstrap script** — run [`scripts/bootstrap-gcp-client.sh <project-id>`](../../scripts/bootstrap-gcp-client.sh) once per project to enable APIs and create the Terraform state bucket.

## Required variables

| Name | Type | Description |
|------|------|-------------|
| `project_id` | `string` | Client GCP project ID. |
| `client_name` | `string` | Short identifier used as a prefix for resource names. |
| `targets_file` | `string` | Local path to the client target list; uploaded to the config bucket on apply. |

## Optional variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `scanner_image` | `string` | `ghcr.io/leansecurity/leansec-nuclei:latest` | Scanner image URI. Pin to a semver tag in production. |
| `region` | `string` | `asia-southeast1` | GCP region for regional resources. |
| `profiles_file` | `string` | `scanner/profiles/profiles.yaml` | Local path to profiles.yaml; uploaded to the config bucket. |
| `schedule_cron` | `string` | `0 2 1-7 * 0` | Cron expression for the scheduled scan. Ignored when `enable_scheduler = false`. |
| `schedule_timezone` | `string` | `UTC` | Scheduler timezone. Ignored when `enable_scheduler = false`. |
| `results_retention_days` | `number` | `365` | Age in days before results bucket objects transition to Nearline. |
| `results_delete_days` | `number` | `730` | Age in days before results bucket objects are deleted. |
| `job_memory` | `string` | `2Gi` | Cloud Run container memory allocation. |
| `job_cpu` | `string` | `1` | Cloud Run container CPU allocation. |
| `job_timeout` | `string` | `3600s` | Cloud Run task timeout. |
| `enable_scheduler` | `bool` | `true` | Provision Cloud Scheduler job + scheduler SA + invoker IAM binding. |
| `enable_wif` | `bool` | `false` | Provision Workload Identity Federation pool, GitHub OIDC provider, and SA binding. Requires `wif_github_repository`. |
| `enable_ar_mirror` | `bool` | `false` | Provision a `google_artifact_registry_repository` for mirroring the GHCR image. |
| `wif_github_repository` | `string` | `""` | GitHub repository (`owner/repo`) authorized to assume the scanner SA via WIF. Required when `enable_wif = true`. |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `config_bucket_name` | `string` | Name of the config bucket. |
| `results_bucket_name` | `string` | Name of the results bucket. |
| `cloud_run_job_name` | `string` | Name of the Cloud Run job. |
| `scheduler_job_name` | `string \| null` | Name of the Cloud Scheduler job; `null` when `enable_scheduler = false`. |
| `scanner_service_account_email` | `string` | Email of the scanner service account. |
| `wif_pool_name` | `string \| null` | Full resource name of the WIF pool; `null` when `enable_wif = false`. |
| `wif_provider_name` | `string \| null` | Full resource name of the WIF GitHub provider; `null` when `enable_wif = false`. |
| `artifact_registry_repository` | `string \| null` | AR repository ID; `null` when `enable_ar_mirror = false`. |

## Example usage

From a private deployment folder, copy of [`deployments/_example/`](../../deployments/_example/):

```hcl
module "nuclei" {
  source = "git::https://github.com/leansecurity/leansecurity-nuclei.git//infra/gcp?ref=v1.0.0"

  project_id    = "client-prod-1234"
  client_name   = "acme"
  scanner_image = "ghcr.io/leansecurity/leansec-nuclei:v1.0.0"
  targets_file  = "${path.module}/targets.txt"

  # enable_wif            = true
  # wif_github_repository = "acme/security-ci"
}
```

## Flag semantics

### `enable_scheduler` (default `true`)

When `true`, the module provisions a Cloud Scheduler job, a dedicated
scheduler service account, and the `run.invoker` IAM binding the
scheduler needs to trigger the Cloud Run job. Disable when scans are
triggered exclusively by an external orchestrator (e.g. another CI job
or an on-demand workflow).

### `enable_wif` (default `false`)

When `true`, the module provisions a Workload Identity Federation pool
with a GitHub OIDC provider, and binds the scanner service account so
that GitHub Actions workflows running in `wif_github_repository` can
assume it without long-lived keys. Disable unless an external CI system
needs to trigger jobs in the client project.

### `enable_ar_mirror` (default `false`)

When `true`, the module provisions an empty Artifact Registry Docker
repository in the client project. **Mirroring is manual** — the
architect pulls the desired GHCR tag, re-tags it for the AR repo, and
pushes it before re-applying with `scanner_image` pointed at the AR
URI. Enable for clients whose policies require in-project container
registry locality.

## See also

- [Setup guide](../../docs/setup-guide.md) — end-to-end walkthrough.
- [Architecture](../../docs/gcp_architecture.md) — design rationale.
- [Bootstrap script](../../scripts/bootstrap-gcp-client.sh) — one-shot project preparation.
- [`deployments/_example/`](../../deployments/_example/) — template for private deployment folders.
