# Report — gha-config-sync-private-repo

Source task: `.claude/tasks/gha-config-sync-private-repo.md`. Full trail: `.claude/scope.md`
(READ) → `.claude/plan.md` (PLAN, architect-approved 2026-07-02) → this file (REPORT).

## What was built

### Architecture decision
- [`decisions/ADR-008-per-client-repo-topology.md`](../decisions/ADR-008-per-client-repo-topology.md) —
  records the client-owned private repo as a second GCP deployment topology alongside the
  existing in-repo `deployments/<client>/` model (not a replacement). Captures the
  architect's decisions: client-owned repos (not `eriklacson` or a shared org), client
  operates their own repo independently post-bootstrap, semver-tag module pinning.
- `.claude/docs/LeanSecurity_Nuclei_seed_document.md:17` updated to describe both
  topologies instead of stating the in-repo model as the only one.

### Phase 1 — `infra/gcp/client-repo-template/`
9 files: `deployment.yaml`, `targets.txt`, `profiles.yaml` (copy of the canonical 7-profile
set), `main.tf` (git-ref module source, pinned `?ref=v1.2.3` placeholder — bump per ADR-008's
semver-tag decision), `backend.tf`, `terraform.tfvars`, `.gitignore`,
`.github/workflows/deploy.yml`, `.github/workflows/plan.yml`.

### Phase 2 — GitHub Actions
- `deploy.yml`: push-to-main + `workflow_dispatch`, WIF-only auth
  (`google-github-actions/auth@v2`), `terraform init` + `apply -auto-approve`, then
  `gcloud storage cp` for both `targets.txt` and `profiles.yaml` to the config bucket.
- `plan.yml`: PR-triggered, WIF-only auth, `terraform plan`, posts/updates a single PR
  comment with the summary line visible and full plan collapsed in `<details>` (resolves
  open question #4 — plan output size).
- No long-lived service account keys anywhere; both workflows use `id-token: write` +
  Workload Identity Federation exclusively, matching the module's existing `enable_wif`
  support.

### Phase 3 — bootstrap sequencing (documented in ADR-008 and plan.md, not code)
Corrected from the task file's original order, which was unworkable given the schema gap
found during READ: **client creates their repo first**, then the architect runs local
bootstrap with `wif_github_repository` already known, then hands off WIF values.

### Phase 4 — `gcp-deploy` skill amendments
- **Schema fix** (found during READ, closed as part of this task):
  `.claude/skills/gcp-deploy/schema/deployment.schema.json` gained
  `features.wif_github_repository`, conditionally required via JSON Schema `if/then` when
  `enable_wif: true`. Without this, Phase 3 had no way for the operator to actually supply
  the value the WIF trust binding depends on — the field existed in the Terraform module
  and the skill's tfvars template, but nowhere in the schema or example YAML.
- `deployment.example.yaml` and `client-repo-template/deployment.yaml` both show the new field.
- `SKILL.md` Step 4 gained a pre-check: confirm the client's repo already exists before an
  `enable_wif: true` apply runs. Step 5's defaults table documents the field as
  required-when-true with no default. Step 11 gained a hand-off block: read
  `wif_provider_name` / `scanner_service_account_email` from `terraform output`, print the
  exact `gh variable set` commands for the client to run in their own repo.
- `README.md` workflow overview and "See also" updated to cross-link ADR-008 and the new template.

## Verification results

| Check | Result |
|---|---|
| `poetry run black --check .` | Pass — 11 files unchanged |
| `poetry run ruff check .` | Pass — no issues |
| `poetry run bandit -r . -x ".venv,venv,build,dist,docs,migrations,tests"` | Pass — 107 pre-existing low-severity `assert`-in-tests findings, all in `tests/`, unrelated to this change (no new findings) |
| `poetry run python -m pytest -q --maxfail=1 --disable-warnings` | Pass — all tests green, no regression (this task added no Python) |
| `deployment.schema.json` self-validates as draft-07 | Pass |
| `client-repo-template/deployment.yaml` validates against schema with real values + `wif_github_repository` present | Pass |
| Negative test: `enable_wif: true` + missing `wif_github_repository` | Correctly rejected — `'wif_github_repository' is a required property` |
| Regression test: `enable_wif: false` without `wif_github_repository` (existing `deployment.example.yaml` shape) | Still validates — no breakage to the unchanged in-repo topology |
| `terraform fmt -check -diff` on `client-repo-template/` | Pass — no formatting diffs |
| `terraform validate` (full, against the real `github.com/...?ref=v1.2.3` source) | **Not run** — that tag doesn't exist yet (repo isn't pushed/tagged); this is expected for a template, not a bug |
| Module wiring check | Static comparison: every variable `client-repo-template/main.tf` passes to the module (`project_id`, `client_name`, `scanner_image`, `targets_file`, `profiles_file`, `enable_wif`, `wif_github_repository`) exists in `infra/gcp/variables.tf` with matching names |
| `deploy.yml` / `plan.yml` YAML syntax | Pass — both parse cleanly |

## Flagged as unresolved / architect-verified only

- **End-to-end real-world test is not possible from this environment.** No GCP credentials,
  no GitHub write access to create a real client repo, no way to exercise WIF trust or run
  `terraform apply` against real infrastructure. Everything above is static/local
  verification; the actual `gh repo create` → bootstrap → hand-off → client push → GHA
  deploy flow needs to be run once, live, by the architect against a real (or test) client.
- **`?ref=v1.2.3` in `client-repo-template/main.tf` is a placeholder.** No release/tag
  workflow exists yet to cut real semver tags of `infra/gcp/`. The architect needs to tag a
  real release before any client repo can actually resolve the module.
- **Two `main.tf` template styles now coexist** (`infra/gcp/_example/`, relative path, for
  the in-repo topology; `infra/gcp/client-repo-template/`, git-ref, for the client-owned
  topology) — flagged explicitly in ADR-008's "Negative / risk" section as a doc-confusion
  risk to watch for, not something structurally preventable.
- **Open questions #1 and #5 from the task file were architect decisions, not implementation
  work** — resolved in conversation (client-owned repos, client self-operates) and recorded
  in ADR-008 and `.claude/plan.md`; no code enforces "who owns the repo" since that's outside
  this repo's control by definition.

## Control ID validation

This task changes deployment/CI tooling only — no scanner output, no JSONL, no new CSFLite
control mappings. `csflite/controls.json` was read during the READ step for context; nothing
here required a change to it.
