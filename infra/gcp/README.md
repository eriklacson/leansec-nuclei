# GCP Infrastructure Module

Provisions a Cloud Run job, optional Cloud Scheduler trigger, two GCS
buckets (config + results), service accounts, IAM bindings, and optional
Workload Identity Federation and Artifact Registry mirror for the
LeanSecurity Nuclei scanner pipeline.

The module is consumed from a per-client deployment folder at
`deployments/<client>/` inside the repo checkout (gitignored).
Copy `_example/` as the starting point. Architects run `terraform apply`
from their workstation; the public repository does not hold cloud credentials.

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
| `scanner_image` | `string` | `ghcr.io/eriklacson/leansec-nuclei:latest` | Scanner image URI. Pin to a semver tag in production. |
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
| `enable_wif` | `bool` | `false` | Provision WIF pool, GitHub OIDC provider, deployer SA with project-admin roles, and the assume binding. Requires `wif_github_repository`. |
| `enable_ar_mirror` | `bool` | `false` | Provision a `google_artifact_registry_repository` for mirroring the GHCR image. |
| `wif_github_repository` | `string` | `""` | GitHub repository (`owner/repo`) authorized to assume the deployer SA via WIF. Required when `enable_wif = true`. |
| `state_bucket_name` | `string` | `""` | GCS bucket holding this deployment's Terraform state. When set alongside `enable_wif`, grants the deployer `objectAdmin` on it so CI can run `terraform init`. |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `config_bucket_name` | `string` | Name of the config bucket. |
| `results_bucket_name` | `string` | Name of the results bucket. |
| `cloud_run_job_name` | `string` | Name of the Cloud Run job. |
| `scheduler_job_name` | `string \| null` | Name of the Cloud Scheduler job; `null` when `enable_scheduler = false`. |
| `scanner_service_account_email` | `string` | Email of the scanner service account. Not the CI identity. |
| `deployer_service_account_email` | `string \| null` | Email of the deployer SA that external CI assumes via WIF; `null` when `enable_wif = false`. This is the client's `GCP_SA_EMAIL`. |
| `wif_pool_name` | `string \| null` | Full resource name of the WIF pool; `null` when `enable_wif = false`. |
| `wif_provider_name` | `string \| null` | Full resource name of the WIF GitHub provider; `null` when `enable_wif = false`. |
| `artifact_registry_repository` | `string \| null` | AR repository ID; `null` when `enable_ar_mirror = false`. |

## Example usage

From a deployment folder at `deployments/<client>/`, copied from [`_example/`](_example/):

```hcl
module "nuclei" {
  source = "../../infra/gcp"

  project_id    = "client-prod-1234"
  client_name   = "acme"
  scanner_image = "ghcr.io/eriklacson/leansec-nuclei:v1.0.0"
  targets_file  = "${path.module}/targets.txt"

  # Client-owned repo topology (ADR-008). state_bucket_name is not optional
  # in practice — without it CI has no access to the state backend.
  # enable_wif            = true
  # wif_github_repository = "acme/security-ci"
  # state_bucket_name     = "client-prod-1234-tfstate-leansecurity-nuclei"
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

When `true`, the module provisions a Workload Identity Federation pool with
a GitHub OIDC provider, **a dedicated deployer service account**, and the
binding that lets GitHub Actions workflows in `wif_github_repository` assume
that account without long-lived keys. This is what enables the client-owned
repo topology of [ADR-008](../../decisions/ADR-008-per-client-repo-topology.md),
where the client's own CI runs `terraform plan` on PRs and `terraform apply`
on merge.

The deployer holds the seven project roles listed by
[`scripts/bootstrap-gcp-client.sh`](../../scripts/bootstrap-gcp-client.sh) —
the same set a human principal needs to apply this module, because it runs
the same plan. That includes `roles/storage.admin`, project-scoped, which
already covers the state bucket — `state_bucket_name` adds a narrower
bucket-scoped grant on top of that. It's currently redundant with
`storage.admin`, but load-bearing if that role is ever narrowed to
something less than project-wide (a tracked follow-up), so set it anyway.

**Why a separate account.** The scanner SA executes third-party Nuclei
templates against live targets and holds two bucket bindings, nothing more.
The deployer is effectively project-admin — `terraform apply` must create
buckets and service accounts, which resource-scoped grants cannot authorize.
Keeping them separate is the point; it is a separation boundary, not a
reduction in what CI can do.

**Bootstrapping.** CI cannot create the identity it authenticates as. An
architect runs one local `terraform apply` to create the deployer SA and its
bindings before the client's first workflow run can succeed.

**Lockout.** The deployer administers the WIF pool that authenticates it and
the service account that is itself. A destructive apply can remove its own
access; recovery is an architect-run local apply.

Prior to this revision the binding targeted the *scanner* SA, and this
section described the flag as being for CI that "needs to trigger jobs."
Neither was functional — the scanner SA has no project roles, and
`roles/run.invoker` goes to the scheduler SA. Deployments applied before
this change must re-apply and update their `GCP_SA_EMAIL` to
`deployer_service_account_email`.

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
- [`_example/`](_example/) — template for deployment folders.
