# Example Deployment — Template

This folder is a **template**, not a deployment. Copy it to
`deployments/<your-client>/` inside the repo checkout before configuring it
for a real client; do not run `terraform apply` from this directory.

## What this template gives you

A minimal Terraform root module that calls the `infra/gcp/` module via a
relative path. Filling in `terraform.tfvars` and `targets.txt`, then
pointing `backend.tf` at a GCS state bucket, produces a working scan
pipeline in a client GCP project.

## How to use it

1. **Copy the folder** to your deployment folder inside the repo:
   ```bash
   cp -r infra/gcp/_example/ deployments/<your-client>/
   cd deployments/<your-client>/
   ```
   The `deployments/<client>/` folder is gitignored — no client data
   will be committed to the public repo.

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

6. **Init + plan + apply** from inside your deployment folder:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

The full step-by-step walkthrough lives in
[`docs/setup-guide.md`](../../docs/setup-guide.md). The module reference
lives in [`infra/gcp/README.md`](../README.md).

## Skill-assisted path

The `/gcp-deploy` Claude Code skill automates steps 2–6 from a
`deployment.yaml` config file. See
[`.claude/skills/gcp-deploy/README.md`](../../.claude/skills/gcp-deploy/README.md).
