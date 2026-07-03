# Client-Owned Deployment Repo — Template

This folder is a **template** for the client-owned GCP deployment topology
described in [ADR-008](../../../decisions/ADR-008-per-client-repo-topology.md)
in the `leansec-nuclei` repo. It is meant to be copied out of that repo and
pushed to a **private repo the client owns** — not committed here, and not
run from inside this checkout.

If you're looking for the other topology — where the deployment stays
inside `leansec-nuclei` under `deployments/<client>/` and the architect
runs `terraform apply` locally — see
[`infra/gcp/_example/`](../_example/) instead. Do not mix the two: this
template resolves the Terraform module by a **pinned git ref**
(`source = "github.com/.../infra/gcp?ref=vX.Y.Z"`), since an external repo
has no relative path back into `leansec-nuclei`. `_example/` resolves it by
relative path and will not work outside a `leansec-nuclei` checkout.

## Who does what

This topology splits work between two roles — see ADR-008 for the full
rationale:

- **The architect** runs a one-time local bootstrap apply against the
  client's GCP project (via the `gcp-deploy` skill in `leansec-nuclei`),
  provisioning the Workload Identity Federation (WIF) trust binding scoped
  to the client's repo, and hands off the resulting values.
- **The client** creates their own private repo, copies this template into
  it, fills in the values the architect provided, and pushes. From then on,
  the client's own GitHub Actions workflows (`deploy.yml`, `plan.yml`) run
  `terraform plan`/`apply` on every PR/merge — the architect is not in that
  loop.

## Sequencing — this order matters

`wif_github_repository` (the client's own `owner/repo` string) must be known
**before** the architect's bootstrap apply, because it's baked into the WIF
trust binding. The client repo must exist first:

1. **Client** creates their private repo (e.g. `gh repo create <owner>/<repo> --private`).
2. **Client** tells the architect the repo's `owner/repo`.
3. **Architect** runs the `gcp-deploy` skill locally with `enable_wif: true`
   and `wif_github_repository: <owner>/<repo>` set.
4. **Architect** hands the client the `terraform output` values: WIF
   provider name, scanner service account email, project ID, region, client
   name.
5. **Client** copies this template's files into their repo, fills in
   `terraform.tfvars` (and `deployment.yaml` for the human-readable record)
   with those values, sets the corresponding repo variables the workflows
   read, and pushes to `main`.
6. All later changes go through PR → merge on the client's own repo.

## Files in this template

| File | Purpose |
|---|---|
| `main.tf` | Calls the `infra/gcp` module by pinned git ref. Declares passthrough variables; do not hardcode real values here. |
| `terraform.tfvars` | Real values for this deployment — must match what the architect used in the initial bootstrap apply (same `project_id`, `client_name`, `wif_github_repository`). |
| `backend.tf` | Points at the GCS state bucket the architect's bootstrap already created. Do not point this at a new bucket — it must be the same state the bootstrap apply wrote to. |
| `deployment.yaml` | Human-readable record of intent, mirroring the `gcp-deploy` skill's config. Not read by the GitHub Actions workflows — it documents what `terraform.tfvars` should contain, and must be kept in sync manually. |
| `targets.txt` | This client's scan targets (URLs/IPs). Edited directly in this repo, no architect involvement needed. |
| `profiles.yaml` | Scan profile definitions — a copy of the canonical set in `scanner/profiles/profiles.yaml`. Override per-client here if needed. |
| `.github/workflows/plan.yml` | Runs `terraform plan` on PRs, posts the summary as a PR comment. WIF-only auth. |
| `.github/workflows/deploy.yml` | Runs `terraform apply` + syncs `targets.txt`/`profiles.yaml` to GCS on merge to `main`. WIF-only auth. |

## Before you push this template anywhere

The `source` ref in `main.tf` is pinned to a specific `leansec-nuclei`
release tag. Check that the tag actually exists
(`git tag -l` in `leansec-nuclei`, or the repo's Releases page) before
relying on it — `terraform init` will fail with `invalid ref` otherwise.
The architect is responsible for keeping this pinned correctly; ask them
before bumping it yourself.

## No long-lived credentials

Both workflows authenticate to GCP exclusively via Workload Identity
Federation (`google-github-actions/auth@v2` + `id-token: write`). No
service account JSON key should ever be stored as a repo secret in this
topology — if you find yourself adding one, something upstream of this
template has gone wrong.
