# Example Deployment — Template

This folder is a **template**, not a deployment. Copy it to your own
private storage before configuring it for a real client; do not run
`terraform apply` from this directory in the public repo.

## What this template gives you

A minimal Terraform root module that calls the GCP infrastructure module
(`infra/gcp/`) from the public `leansecurity-nuclei` repo via a pinned
semver source ref. Filling in `terraform.tfvars` and `targets.txt`, then
pointing `backend.tf` at a GCS state bucket, produces a working scan
pipeline in a client GCP project.

## How to use it

1. **Copy the folder** to your private storage:
   ```bash
   cp -r deployments/_example/ /path/to/private/<client>/
   ```

2. **Bootstrap the client GCP project** (one-time):
   ```bash
   ./scripts/bootstrap-gcp-client.sh <your-project-id>
   ```
   Enables required APIs and creates the Terraform state bucket.

3. **Edit `terraform.tfvars`** with real values:
   - `project_id` — the client GCP project ID
   - `client_name` — a short identifier used as a resource-name prefix
   - `scanner_image` — pin to a semver tag (e.g. `:v1.0.0`); avoid `:latest` in production

4. **Edit `backend.tf`** so `bucket =` matches the state bucket created
   by the bootstrap script.

5. **Populate `targets.txt`** with real external URLs.

6. **Init + plan + apply** from inside your copy of the folder:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

The full step-by-step walkthrough, including troubleshooting, lives in
[`docs/setup-guide.md`](../../docs/setup-guide.md). The module reference
lives in [`infra/gcp/README.md`](../../infra/gcp/README.md).

## Why a separate private copy

Per-client deployment configuration (project IDs, target lists, IAM
grants) doesn't belong in the public repository. Keeping these in
client-controlled storage outside this repo is the canonical pattern;
the public repo holds only the reusable module and this template.
