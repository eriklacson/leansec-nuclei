# Plan: GitHub Actions Config Sync via Per-Client Private Repo (Option C)

## Goal

Offload `targets.txt`, `profiles.yaml` sync to GCS — and `terraform apply` — to GitHub Actions. Each client gets a dedicated private repository that holds their config files. GHA in that repo drives all redeployments. The main `leansec-nuclei` repo and its gitignore policy are unchanged.

---

## Architecture

```
leansec-nuclei (public/private, this repo)
  infra/gcp/             ← Terraform module source (unchanged)
  .claude/skills/gcp-deploy/  ← Still used for first-time bootstrap only

leansec-nuclei-<client> (NEW, private repo per client)
  deployment.yaml        ← operator config (replaces local deployments/<client>/)
  targets.txt            ← one URL per line
  profiles.yaml          ← scan profile overrides
  .github/workflows/
    deploy.yml           ← terraform apply + GCS sync on push to main
    plan.yml             ← terraform plan on PR
```

The per-client repo **references** the Terraform module in this repo by version-pinned Git ref, not by local relative path. GHA clones both repos and runs `terraform apply` from the client repo context.

---

## Phases

### Phase 1 — Per-client repo template

Create `infra/gcp/client-repo-template/` in this repo. This is a one-time-copy scaffold, not a GitHub template repo (no special GitHub config needed).

**Files to create:**

```
infra/gcp/client-repo-template/
  deployment.yaml          ← same schema as existing deployment.example.yaml
  targets.txt              ← placeholder (one comment line)
  profiles.yaml            ← copy of scanner/_example/profiles.yaml
  main.tf                  ← references module via git source, not relative path
  backend.tf               ← parameterized by client_name + gcp_project_id
  terraform.tfvars         ← populated from deployment.yaml at bootstrap time
  .gitignore               ← ignore .terraform/, tfplan, *.tfstate
  .github/
    workflows/
      deploy.yml           ← apply + sync on push to main
      plan.yml             ← plan-only on PR
```

**`main.tf` module source change.** The existing generated `main.tf` uses a local relative path:
```hcl
module "leansec_nuclei" {
  source = "../../infra/gcp"
  ...
}
```
The client-repo version must use a Git source with a pinned ref:
```hcl
module "leansec_nuclei" {
  source = "github.com/eriklacson/leansec-nuclei//infra/gcp?ref=v1.2.3"
  ...
}
```
The `ref` value must be bumped in the client repo whenever the Terraform module in this repo changes in a breaking way.

---

### Phase 2 — GitHub Actions workflows (inside client-repo-template)

**`deploy.yml`** — triggers on push to main and `workflow_dispatch`:

1. Checkout the client repo
2. Authenticate to GCP via WIF (`google-github-actions/auth`)
3. `terraform init` (backend already configured in `backend.tf`)
4. `terraform apply -auto-approve`
5. `gcloud storage cp targets.txt gs://<bucket>/targets/targets.txt`
6. `gcloud storage cp profiles.yaml gs://<bucket>/profiles/profiles.yaml`

**`plan.yml`** — triggers on PR:

1. Steps 1–3 above
2. `terraform plan -out=tfplan`
3. Post plan output as a PR comment (using `actions/github-script` or `hashicorp/setup-terraform`'s built-in comment feature)

**GCP authentication method:** Workload Identity Federation only. No long-lived service account JSON keys committed or stored as secrets. The WIF provider and SA email are stored as GitHub repository variables (non-secret):
- `GCP_WIF_PROVIDER` — WIF provider resource name
- `GCP_SA_EMAIL` — scanner service account email
- `GCP_PROJECT_ID` — target GCP project
- `GCP_REGION` — deployment region
- `GCP_CLIENT_NAME` — client name prefix (used to derive bucket name)

---

### Phase 3 — Bootstrap process update

The first-time setup sequence for a new client changes to:

1. **Operator runs gcp-deploy skill locally** (unchanged) to:
   - Create the GCP project resources (Cloud Run, GCS buckets, IAM)
   - Enable WIF (`enable_wif: true` in deployment.yaml)
   - Get the WIF provider resource name and SA email from terraform output

2. **Operator creates the private client repo** by copying `infra/gcp/client-repo-template/`:
   ```bash
   gh repo create leansec-nuclei-<client> --private
   cp -r infra/gcp/client-repo-template/. /path/to/leansec-nuclei-<client>/
   ```

3. **Operator sets GitHub repo variables** (not secrets — WIF provider and SA email are not sensitive):
   ```bash
   gh variable set GCP_WIF_PROVIDER --body "projects/.../locations/global/workloadIdentityPools/..."
   gh variable set GCP_SA_EMAIL     --body "<client>-nuclei-scanner@<project>.iam.gserviceaccount.com"
   gh variable set GCP_PROJECT_ID   --body "<project>"
   gh variable set GCP_REGION       --body "asia-southeast1"
   gh variable set GCP_CLIENT_NAME  --body "<client>"
   ```

4. **All future redeployments happen via PR → merge** to the client repo. No local gcloud or terraform needed after this point.

---

### Phase 4 — Update gcp-deploy skill

Amend the skill's Step 11 (report results) to include instructions for setting up the client repo after a successful first apply:

- Print the WIF provider resource name and SA email from `terraform output`
- Show the `gh repo create` + `gh variable set` commands pre-filled with actual values
- Note that future config changes go through the client repo, not the local deployment folder

The skill remains the tool for Phase 3 step 1 (first-time bootstrap). It does not need to be replaced.

---

## Open questions (resolve before implementation)

1. **Repo ownership.** Does each client repo live under the `eriklacson` GitHub account, or under a separate org (e.g., `leansec-clients`)? An org is cleaner for access control but adds setup friction.

2. **Module pinning strategy.** Pin the Terraform module to a semver tag (`?ref=v1.2.3`) or a commit SHA? Tags are human-readable but require a release workflow. SHA is exact but harder to read.

3. **WIF bootstrap ordering.** WIF provisioning requires `enable_wif: true` in the first local apply. Should the gcp-deploy skill enforce this (error if `enable_wif` is false when scaffolding the client repo), or leave it optional?

4. **`terraform plan` PR comments.** The plan output can be large. Collapse it in the PR comment or truncate to summary only?

5. **Multiple client repos — access control.** Who gets write access to each client repo? Currently the architect controls all deployments. Define the policy before creating any client repos.

---

## Out of scope for this plan

- Migrating the existing `mdi` deployment to a client repo (separate task — do after template is validated)
- AWS or Azure equivalents
- Automated module version bumps across client repos
- Any changes to `scanner/`, `docker/`, or CI (`ci.yaml`, `publish-image.yaml`)
