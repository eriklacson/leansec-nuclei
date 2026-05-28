# Plan — gcp-cloud-deploy

Companion to `.claude/scope.md`. Open questions resolved 2026-05-28; confirmed decisions captured in **Assumptions** below.

## Assumptions (confirmed)

1. **B2 is verification-only.** No edits to `docker/entrypoint.sh`. Deliverable becomes an end-to-end local-Docker run that confirms JSONL filenames match `profiles.yaml` keys exactly.
2. **`.gitignore` rewrite:** replace blanket `deployments/` ignore with `deployments/*` + `!deployments/_example/` (B8).
3. **B1 phrasing** — env blocks aren't literally truncated; they're single-line and fail `fmt`. Rewrite as multi-line `env { name = ...; value = ... }` blocks.
4. **`deployments/_example/README.md` already exists** — refresh, not create (B7).
5. **`docs/` directory** — create on first write under D3 (no permission needed).
6. **All six `decisions_to_confirm` defaults accepted as a bundle:**
   - Image tag scheme: `:latest` + `:<short-sha>` + `:vX.Y.Z`
   - GHCR image name: `ghcr.io/leansecurity/nuclei-scanner`
   - Bootstrap: bash script at `scripts/bootstrap-gcp-client.sh`
   - Delete `infra/gcp/workflows/scanner-image.yml`, write `.github/workflows/publish-image.yaml` from scratch
   - `enable_ar_mirror` default `false`
   - Append three locked design decisions verbatim to `.claude/docs/LeanSecurity_Nuclei_seed_document.md`

## Sequencing

Strict: `build → documentation → setup-guide`. Each workstream's acceptance must pass before the next begins. Within `build`, ordering chosen to minimize rework: defects + module first, then CI workflows that reference the module, then example folder, then placeholder cleanup.

---

## Workstream B — Build

### B1. Fix Terraform env blocks (`infra/gcp/main.tf`)

**Action:** rewrite lines 101-105 of the Cloud Run job `containers` block. Each `env` entry becomes a multi-line block matching v6+ provider schema. Order preserved.

**Form per entry:**
```hcl
env {
  name  = "CLOUD_PROVIDER"
  value = "gcp"
}
```

**Verify:** `terraform validate` + `terraform fmt -check` in `infra/gcp/`.

---

### B3. Rewrite `infra/gcp/` module

Done as a unit with B1 since both touch `main.tf`. Reorders into resource groups matching the module shape.

**`variables.tf` additions:**
- `enable_scheduler` — `bool`, default `true`. Description per project.yaml.
- `enable_wif` — `bool`, default `false`.
- `enable_ar_mirror` — `bool`, default `false`.
- `scanner_image` description updated to: "Scanner image URI (GHCR by default; any registry supported)." Default: `ghcr.io/leansecurity/nuclei-scanner:latest`. No validation block constraining the URI.

**`main.tf` changes:**
- Move `terraform { required_providers { ... } }` block out to new `versions.tf` (pin `google ~> 6.0` for v6+ env block schema compatibility; matches B1 fix). Note: scope's "google ~> 5.0" is current state. Bumping to v6 is required for the env block schema fix; flag in report if architect prefers staying on v5.
- Cloud Scheduler job + scheduler service account + `google_cloud_run_v2_job_iam_member.scheduler_invoker`: gate behind `count = var.enable_scheduler ? 1 : 0`.
- Add WIF resources behind `count = var.enable_wif ? 1 : 0`: `google_iam_workload_identity_pool`, `google_iam_workload_identity_pool_provider`, `google_service_account_iam_member` binding the WIF principal to the scanner SA.
- Add AR mirror behind `count = var.enable_ar_mirror ? 1 : 0`: `google_artifact_registry_repository` (Docker format, region from `var.region`).
- `scanner_image` flows straight into `containers.image` — no path validation.
- Remove `var.profiles_file` upload? **No** — current module uploads `profiles.yaml` to the config bucket. Project.yaml does not mention removing it, so preserve.

**`outputs.tf` changes:**
- `scheduler_job_name`: change to `value = var.enable_scheduler ? google_cloud_scheduler_job.nuclei[0].name : null`.
- Other outputs unchanged.

**`versions.tf` (new):**
```hcl
terraform {
  required_version = ">= 1.8"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
```

**Verify:**
- `terraform validate` and `terraform fmt -check` pass.
- `terraform plan` with no flags: buckets + Cloud Run job + scheduler + SAs + IAM bindings appear; no AR repo, no WIF.
- `terraform plan -var='enable_scheduler=false'`: scheduler + scheduler SA + invoker binding absent.
- `terraform plan -var='enable_wif=true'`: WIF pool, provider, SA binding present.
- `terraform plan -var='enable_ar_mirror=true'`: AR repo present.

(Plan dry-runs use `terraform plan -refresh=false` against fake `project_id`/`client_name`/`targets_file` tfvars; no GCP credentials needed.)

---

### B2. Verify profile-name alignment (no code change)

**Action:** confirm by inspection + dry-run:
1. Read `scanner/profiles/profiles.yaml` and list all `output:` values.
2. Confirm each matches its profile key.
3. Build local Docker image, run with `CLIENT=_validation` and `CLOUD_PROVIDER=local`, list produced JSONL filenames.
4. Confirm filename set equals `{baseline_web,patch_cve,identity_remote_access,data_protection,transport_security,owasp_top10_core,vuln_monitoring}_<YYYY-MM>.jsonl`.

**Acceptance:** documented confirmation in report; no file edits.

---

### B4. Delete `infra/gcp/workflows/deploy.yml`

**Action:** `git rm infra/gcp/workflows/deploy.yml`.

**Verify:** file absent; `git status` clean for that path.

---

### B5. Replace scanner-image workflow

**Action:**
1. `git rm infra/gcp/workflows/scanner-image.yml`.
2. Write new `.github/workflows/publish-image.yaml`.

**`publish-image.yaml` shape:**
- Trigger: `push` to `main` with paths `docker/**`, `scanner/**`; and `push` of tags `v*`.
- Permissions: `contents: read`, `packages: write`.
- Steps:
  - `actions/checkout@v4`
  - `docker/setup-buildx-action@v3`
  - `docker/login-action@v3` with `registry: ghcr.io`, `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`
  - `docker/metadata-action@v5` to compute tags: `type=raw,value=latest,enable={{is_default_branch}}`, `type=sha,format=short`, `type=semver,pattern={{version}}`
  - `docker/build-push-action@v6` with `context: .`, `file: docker/Dockerfile.local`, `push: true`, tags from metadata-action
- Image name: `ghcr.io/leansecurity/nuclei-scanner`.

**Verify:**
- `actionlint .github/workflows/publish-image.yaml` passes.
- Old `infra/gcp/workflows/scanner-image.yml` absent.
- `verified_by: architect` — first real CI push to GHCR.

---

### B6. `scripts/bootstrap-gcp-client.sh`

**Action:** create `scripts/` directory, write executable bash script.

**Contract:**
- Args: `$1` project_id (required), `$2` region (default `asia-southeast1`), `$3` state bucket name (default `${project_id}-tfstate-leansecurity-nuclei`).
- Behavior:
  1. `set -euo pipefail` at top.
  2. Print usage and exit 1 if no args; print usage and exit 0 if `--help`.
  3. `gcloud config set project "$project_id"`.
  4. `gcloud services enable run.googleapis.com storage.googleapis.com iam.googleapis.com cloudscheduler.googleapis.com iamcredentials.googleapis.com sts.googleapis.com artifactregistry.googleapis.com`.
  5. Create GCS state bucket idempotently (`gcloud storage buckets describe` → create on not-found, with `--uniform-bucket-level-access` and versioning enabled via `gcloud storage buckets update --versioning`).
  6. Print IAM-grant message: roles the client admin must grant the executing principal (`roles/run.admin`, `roles/iam.serviceAccountAdmin`, `roles/storage.admin`, `roles/cloudscheduler.admin`, `roles/iam.workloadIdentityPoolAdmin`, `roles/artifactregistry.admin`).
  7. Print next steps (clone `_example/`, populate tfvars, `terraform init`).
- Header comment block documents purpose, inputs, prerequisites.
- `chmod +x`.

**Verify:**
- `shellcheck scripts/bootstrap-gcp-client.sh` passes.
- Run with no args → usage + exit non-zero.
- Run with `--help` → usage + exit 0.
- `verified_by: architect` — execution against a fresh GCP test project.

---

### B7. Refresh `deployments/_example/`

**Action:** rewrite files in place.

- `main.tf` — module call with `source = "git::https://github.com/leansecurity/leansecurity-nuclei.git//infra/gcp?ref=v1.0.0"`, all variable assignments use placeholders.
- `terraform.tfvars` — placeholder values (`project_id = "<your-project-id>"`, `client_name = "<client>"`, `scanner_image = "ghcr.io/leansecurity/nuclei-scanner:v1.0.0"`, `targets_file = "targets.txt"`).
- `backend.tf` — GCS backend pointing at `<your-project-id>-tfstate-leansecurity-nuclei`.
- `targets.txt` — single example line: `https://example.com`.
- `README.md` — refresh to state: template only, copy to private storage, do not deploy from here; reference setup guide.

**Verify:**
- No client-identifying data anywhere.
- Copy to `/tmp/_example_test/`, replace placeholders with dummies, run `terraform init -backend=false` then `terraform validate` — passes.
- README explicitly states folder is a template, not a live deployment.

---

### B8. Remove `deployments/mdi/` and adjust `.gitignore`

**Actions:**
1. `git rm -r deployments/mdi/`.
2. Edit `.gitignore`: replace the `deployments/` line with:
   ```
   deployments/*
   !deployments/_example/
   ```
   (Preserves the spirit — client folders ignored — while letting `_example/` be tracked and clearing the auto-discovery contradiction.)

**Verify:**
- `deployments/mdi/` absent.
- `git status` shows `_example/` tracked, no other deployment folders untracked-but-now-staged.
- `git check-ignore deployments/foo` returns hit; `git check-ignore deployments/_example` returns no hit.

---

### Workstream-B acceptance gate

Before moving to documentation:
- `poetry run black --check . && poetry run ruff check . && poetry run bandit -r . --severity-level high && poetry run pytest` passes.
- `terraform validate` + `terraform fmt -check` in `infra/gcp/` pass.
- `actionlint .github/workflows/*.yaml` passes.
- `shellcheck scripts/*.sh docker/*.sh` passes.
- Local CLI: `poetry run python scanner/scan.py _validation` produces correctly-named JSONL in `results/_validation/<YYYY-MM>/`.
- Local Docker (`CLOUD_PROVIDER=local`) produces the same filenames.

---

## Workstream D — Documentation

### Pre-step: append locked decisions to seed doc

Append three verbatim decisions (per `decisions_to_confirm.seed_document_locked_decisions.text`) to `.claude/docs/LeanSecurity_Nuclei_seed_document.md` under a new "Locked design decisions — gcp-cloud-deploy" section. Exact wording from project.yaml.

### D1. `README.md`

**Action:** edit in place.

- Remove "Cloud Deployment — Next Phase" "not yet available" section (lines ~124-126); replace with a Cloud-Automated mode section.
- Update the mode table row for Cloud: link to setup guide instead of "Next phase / not yet available."
- Add operating-model paragraph: public repo, private deployments, architect-driven `terraform apply`.
- Add image-distribution note: `ghcr.io/leansecurity/nuclei-scanner`, pin semver in production.
- Cross-links: `docs/setup-guide.md`, `docs/gcp_architecture.md`, `infra/gcp/README.md`.
- Preserve all existing Local CLI + Local Docker content unchanged.

**Verify:** no "not yet available" string remains in cloud context; four cross-links resolve.

### D2. `infra/gcp/README.md`

**Action:** rewrite (file currently exists as scaffold; replace content).

Sections in order: Purpose · Prerequisites · Required variables (table) · Optional variables (table: `enable_scheduler`, `enable_wif`, `enable_ar_mirror`, `region`, `schedule_cron`, `schedule_timezone`, `results_retention_days`, `results_delete_days`, `job_memory`, `job_cpu`, `job_timeout`, `profiles_file`) · Outputs (table) · Example usage (module-call snippet copy-pasteable into a private deployment folder) · Flag semantics (when to enable WIF, when to enable AR mirror).

**Verify:** every variable in `variables.tf` has a row; every output in `outputs.tf` has a row; example main.tf parses cleanly when copied + dummy-substituted.

### D3. `docs/gcp_architecture.md`

**Action:** create `docs/` directory + new file. Source: `.claude/docs/gcp-cloud-deploy-brief.html`.

Sections retained: Context and intent · Operating model (public repo / private deployments) · Runtime scan execution flow · Module flags · Public-repo CI/CD model · Per-client onboarding workflow · See also (cross-links).

Sections omitted: §7 (known defects), §8 (scope boundary), §9 (acceptance criteria), §10 (open decisions).

Diagrams: convert SVG to mermaid where structurally simple; embed inline SVG otherwise.

**Verify:** renders on GitHub markdown viewer; all cross-links resolve; no open-questions or implementation-TODOs language.

### Workstream-D acceptance gate

All D1-D3 acceptance criteria pass; no dead links; doc text reflects the actual B-workstream output (re-check after build is merged).

---

## Workstream S — Setup Guide

### S1. `docs/setup-guide.md`

**Action:** new file under `docs/`. Eleven ordered steps, plus Ongoing Operations and Troubleshooting sections.

Steps: Prerequisites · 1) bootstrap GCP project (`scripts/bootstrap-gcp-client.sh`) · 2) copy `_example/` to private storage · 3) configure tfvars · 4) configure backend.tf · 5) populate targets.txt · 6) `terraform init` · 7) `terraform plan` and review · 8) `terraform apply` · 9) trigger first scan (`gcloud run jobs execute`) · 10) verify JSONL in results bucket · 11) confirm scheduler shows next run time.

Ongoing Operations: changing targets, bumping image version, disabling scheduler.

Troubleshooting (5 required failure modes): API not enabled · IAM permission denied · state bucket access denied · scanner image pull failure · Cloud Run job timeout.

Constraints: every command copy-pasteable with angle-bracket placeholders; every step has an expected-output snippet; no LeanSecurity-internal references.

**Verify:** renders on GitHub; no real values; cross-links to README, gcp_architecture, module README resolve; troubleshooting covers all five required modes. `verified_by: architect` — fresh-project walkthrough.

---

## Verification matrix

| Gate | Command | Workstream |
|------|---------|-----------|
| Python lint/test | `poetry run black --check . && poetry run ruff check . && poetry run bandit -r . --severity-level high && poetry run pytest` | B (continuous) |
| Terraform | `terraform validate` + `terraform fmt -check` (in `infra/gcp/`) | B1, B3 |
| Workflows | `actionlint .github/workflows/*.yaml` | B5 |
| Bash | `shellcheck scripts/*.sh docker/*.sh` | B6 |
| Local CLI | `poetry run python scanner/scan.py _validation` | B (regression) |
| Local Docker | `docker build` + `docker run CLOUD_PROVIDER=local` | B2, B (regression) |
| Markdown links | manual cross-link audit | D, S |

Architect-only gates (not run by Claude Code): B5 first GHCR push · B6 against real GCP project · S1 end-to-end walkthrough · seed-doc §9 items 4-13.

---

## Risks and watchpoints

1. **Provider version bump from `~> 5.0` to `~> 6.0`** in `versions.tf` — required for the env-block schema fix B1 is targeting. If architect prefers staying on v5, the env-block rewrite stays valid (the multi-line block syntax works on both) but the rationale weakens. Flag in report.
2. **`profiles_file` variable in `variables.tf`** — kept, since module still uploads profiles.yaml to the config bucket. If the open-source story is "profiles baked into image," this variable is dead weight. Out of scope per scope.md; flag in report only.
3. **Doc-build drift** — D-workstream must run *after* B-workstream merges, so variable/output tables reflect the real `variables.tf` and `outputs.tf`. Enforce by sequencing.
4. **`_example/.env.example` referenced in current README.md** — that file doesn't appear in the working tree (only `backend.tf`, `main.tf`, `README.md`, `targets.txt`, `terraform.tfvars`). README.md instructions for `cp deployments/_example/.env.example ...` are broken. Not in B7 scope as written, but D1's README rewrite should drop or fix that paragraph. Will be handled as part of D1.

---

## Deliverable checklist

**Build (8):** B1 env fix · B2 profile-alignment verification · B3 module rewrite + new variables + versions.tf · B4 delete deploy.yml · B5 publish-image.yaml + delete scanner-image.yml · B6 bootstrap-gcp-client.sh · B7 refresh _example/ · B8 remove mdi/ + fix .gitignore.

**Documentation (3 + seed-doc edit):** seed doc locked-decisions append · D1 README.md cloud section · D2 infra/gcp/README.md module reference · D3 docs/gcp_architecture.md.

**Setup guide (1):** S1 docs/setup-guide.md.

**Report:** `report-gcp-cloud-deploy.md` summarizing verification results, flagged risks, architect-verified items still outstanding.
