---
name: gcp-deploy
description: >
  Deploy the leansecurity-nuclei pipeline to GCP. Use this skill when the
  operator says "deploy this to GCP", "run the GCP deployment", "apply the
  gcp-deploy skill", "set up the scanner on GCP", or invokes /gcp-deploy.
  Do NOT trigger on unrelated GCP questions or general Terraform work.
version: 1
---

# gcp-deploy skill

Orchestrates a complete GCP deployment of the leansecurity-nuclei pipeline
from a high-level `deployment.yaml`. Reads operator intent, validates it,
renders Terraform inputs, and applies with explicit confirmation.

## Skill constant

```
DEFAULT_SCANNER_IMAGE: ghcr.io/eriklacson/leansec-nuclei:latest
```

Update this value at each skill release to match the latest published semver tag.

---

## When to use this skill

Trigger phrases (intent-triggered):
- "deploy this to GCP"
- "run the GCP deployment"
- "apply the gcp-deploy skill"
- "set up the scanner on GCP"
- "deploy [client] to GCP"

Also triggered by the `/gcp-deploy` slash command.

Do **not** trigger on:
- General Terraform questions
- Non-GCP cloud questions
- Questions about the scanner or CSFLite controls
- Requests to rebuild or push the scanner image

---

## Prerequisites — verify before starting

Before step 1, confirm:

1. **gcloud installed and authenticated**
   - `gcloud version` succeeds
   - `gcloud auth list` shows an active account
   - If not: instruct operator to run `gcloud auth login` and `gcloud auth application-default login`

2. **terraform installed**
   - `terraform version` succeeds
   - If not: direct operator to https://developer.hashicorp.com/terraform/install

3. **Operator is in a deployment folder inside the repo checkout**
   - Current directory should be `deployments/<client>/` within the leansec-nuclei repo
   - The skill resolves the Terraform module via the relative path `../../infra/gcp`
   - If the operator is outside the repo, explain the expected folder structure before continuing

4. **Python 3 available** (used for YAML validation and template substitution)
   - `python3 --version` succeeds
   - If not, `sed` is the fallback — note this in the substitution step

---

## Workflow

### Step 1 — Detect deployment folder state

Check whether `deployment.yaml` exists in the current working directory.

- **Success:** `deployment.yaml` found → proceed to step 1b.
- **Failure (file missing):** Offer to scaffold (step 2). Do not proceed to step 1b until `deployment.yaml` exists and the operator has populated it.

---

### Step 1b — Confirm profiles.yaml placement

Check whether `profiles.yaml` exists in the current deployment folder:

```bash
ls profiles.yaml 2>/dev/null && echo "found" || echo "not found"
```

**If `profiles.yaml` is present:**

Confirm to the operator:

> "`profiles.yaml` found in this deployment folder — the scanner will use these client-specific profiles for this deployment."

Proceed to step 3.

**If `profiles.yaml` is absent:**

Inform the operator:

> "No `profiles.yaml` found in this deployment folder. The scanner will fall back to the global default at `scanner/profiles/profiles.yaml` (all 7 profiles, default rate limits).
>
> To customize scan profiles for this client, copy the template:
> ```bash
> cp "$REPO_ROOT/scanner/_example/profiles.yaml" ./profiles.yaml
> ```
> Then edit `profiles.yaml` to select the profiles and settings you want.
>
> **Proceed with the global default, or customize profiles first?**"

- **Operator confirms proceed with global default** → proceed to step 3.
- **Operator wants to customize** → stop here. Ask them to copy and edit the template, then re-invoke the skill.
- **Do not proceed to step 3 until the operator has made an explicit choice.**

---

### Step 2 — Scaffold from `_example/` (only if deployment.yaml is missing)

Copy the GCP deployment template into the current directory:

```bash
# Resolve repo root from the skill's own location
REPO_ROOT="$(git rev-parse --show-toplevel)"
cp -r "$REPO_ROOT/infra/gcp/_example/." .
cp "$REPO_ROOT/.claude/skills/gcp-deploy/templates/deployment.example.yaml" ./deployment.yaml
```

Then:
1. Inform the operator that `deployment.yaml` has been created from the template.
2. Show them the fields they must populate: `deployment.client_name`, `deployment.gcp_project_id`.
3. Ask them to populate the file and targets.txt, then re-invoke the skill.
4. **Stop here.** Do not continue the workflow until the operator re-invokes.

- **Success:** `deployment.yaml` created, operator instructed to populate it.
- **Failure:** `_example/` not found → the repo checkout may be incomplete. Instruct operator to verify `REPO_ROOT/infra/gcp/_example/` exists.

---

### Step 3 — Validate `deployment.yaml` against schema

Resolve paths:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SCHEMA="$REPO_ROOT/.claude/skills/gcp-deploy/schema/deployment.schema.json"
```

Run validation using Python jsonschema:

```bash
python3 -c "
import json, sys
import yaml
try:
    from jsonschema import validate, ValidationError
except ImportError:
    sys.exit('jsonschema not installed: pip install jsonschema pyyaml')
schema = json.load(open('$SCHEMA'))
doc = yaml.safe_load(open('deployment.yaml'))
try:
    validate(doc, schema)
    print('validation passed')
except ValidationError as e:
    sys.exit(f'validation failed: {e.message} (path: {\" -> \".join(str(p) for p in e.absolute_path)})')
"
```

- **Success:** "validation passed" — proceed to step 4.
- **Failure:** Print the exact field path and error message to the operator. **Stop.** Do not make any gcloud or terraform calls. Ask the operator to fix the YAML and re-invoke.

---

### Step 4 — Run `scripts/bootstrap-gcp-client.sh` if not already done

Ask the operator: *"Has the GCP project already been bootstrapped (APIs enabled, Terraform state bucket created)? If you're not sure, it's safe to re-run — the script is idempotent."*

If operator confirms bootstrap is needed or is unsure:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
GCP_PROJECT_ID="<value from deployment.yaml deployment.gcp_project_id>"
REGION="<value from deployment.yaml deployment.region, default asia-southeast1>"
"$REPO_ROOT/scripts/bootstrap-gcp-client.sh" "$GCP_PROJECT_ID" "$REGION"
```

Read the IAM grants section the script prints and relay it to the operator — they or their GCP admin must grant those roles before `terraform apply` will succeed.

- **Success:** Script exits 0.
- **Failure:** Surface the gcloud error verbatim. Common causes: not authenticated (`gcloud auth login`), insufficient IAM, project ID typo in `deployment.yaml`. Stop and ask operator to resolve.

---

### Step 5 — Render `terraform.tfvars`, `backend.tf`, `main.tf`

Read all values from `deployment.yaml`. Apply defaults for any optional fields:

| Field | Default |
|---|---|
| `deployment.region` | `asia-southeast1` |
| `scanner.image` | `ghcr.io/eriklacson/leansec-nuclei:latest` |
| `features.enable_scheduler` | `true` |
| `features.enable_wif` | `false` |
| `features.enable_ar_mirror` | `false` |
| `schedule.cron` | `0 2 1-7 * 0` |
| `schedule.timezone` | `Etc/UTC` |
| `targets.file` | `./targets.txt` |
| `wif_github_repository` | `""` (empty — harmless when enable_wif is false) |

Use the templates in `$REPO_ROOT/.claude/skills/gcp-deploy/templates/`. Substitute every `{{placeholder}}` with the resolved value. Write the rendered files into the current deployment folder, overwriting any existing versions.

Use Python for substitution (preferred):

```python
import re, yaml, pathlib

deployment_yaml = yaml.safe_load(pathlib.Path("deployment.yaml").read_text())
# ... extract fields with defaults ...
# for each template: read, substitute, write
```

If Python is unavailable, use `sed -e 's/{{placeholder}}/value/g'` for each placeholder.

Each rendered file starts with a header comment:
```
# GENERATED BY gcp-deploy skill from ./deployment.yaml — do not edit directly.
# Re-running the skill regenerates this file.
```

Files written:
- `./terraform.tfvars` (from `tfvars.tmpl`)
- `./backend.tf` (from `backend.tf.tmpl`)
- `./main.tf` (from `main.tf.tmpl`)

- **Success:** Three files written, headers confirm generation timestamp.
- **Failure:** Missing required YAML field (should not occur after step 3 passed). If it does, report the field and stop.

---

### Step 6 — `terraform init`

```bash
terraform init
```

- **Success:** Output contains "Terraform has been successfully initialized."
- **Failure scenarios:**
  - *Backend bucket not found:* Bootstrap may not have run or used a different project ID. Re-check step 4 and verify bucket name matches `<gcp_project_id>-tfstate-leansecurity-nuclei`.
  - *Module not found:* Verify the relative path `../../infra/gcp` resolves from the current folder to the `infra/gcp/` directory in the repo. The operator must be inside the repo checkout at `deployments/<client>/`.
  - *Authentication error:* Run `gcloud auth application-default login`.

---

### Step 7 — `terraform plan`

```bash
terraform plan -out=tfplan 2>&1 | tee tfplan.txt
```

- **Success:** Plan completes; output ends with "Plan: N to add, N to change, N to destroy."
- **Failure:** Surface the full error. Common causes: IAM roles not yet granted (step 4 IAM message), APIs not enabled (re-run bootstrap), credential expiry.

---

### Step 8 — Summarize plan in chat

Present a structured summary to the operator. **Do not bury important details in counts.**

Format:

```
## Terraform plan summary

**Resources to create:** N
**Resources to modify:** N
**Resources to destroy:** N

### ⚠️ IAM bindings being created
(list each — role, member, resource)

### ⚠️ Destructive changes (replacements / deletions)
(list each — resource name, change type, reason if shown)
If none: "None."

### Public access policies
(list any resources with allUsers or allAuthenticatedUsers bindings)
If none: "None."

### Resources created (summary)
- Cloud Run job: <client_name>-nuclei-scan
- GCS config bucket: <client_name>-nuclei-config
- GCS results bucket: <client_name>-security-scans
- Scanner service account: <client_name>-nuclei-scanner
- (if enable_scheduler) Cloud Scheduler job + scheduler SA
- (if enable_wif) WIF pool + provider + SA binding
- (if enable_ar_mirror) Artifact Registry repository

Full plan output is available — ask to see it if needed.
```

- **Success:** Summary presented, operator has enough information to make an informed decision.

---

### Step 9 — Ask operator to confirm before apply

**Mandatory. Never skip.**

Ask explicitly:

> "Ready to apply? This will provision the resources listed above in GCP project `<gcp_project_id>`.
> Reply **yes** to proceed or **no** to stop."

Wait for the operator's response before proceeding.

- **Explicit affirmative** ("yes", "go ahead", "apply", "do it"): proceed to step 10.
- **Anything else** ("no", silence, a question, a modification request): **do not apply.** Address the operator's concern, then return to step 8 or earlier as needed.

---

### Step 10 — `terraform apply`

Only reached after explicit confirmation in step 9.

```bash
terraform apply tfplan
```

- **Success:** Output ends with "Apply complete! Resources: N added, N changed, N destroyed."
- **Failure:** Surface the full error output. Note that Terraform may have partially applied changes — state is not necessarily clean. Advise the operator to run `terraform show` to inspect current state and assess whether manual cleanup is needed before retrying.

---

### Step 11 — Report results and next steps

Present a completion summary:

```
## Deployment complete

**GCP project:** <gcp_project_id>
**Region:** <region>

**Resources deployed:**
- Cloud Run job: <client_name>-nuclei-scan
- Config bucket: gs://<client_name>-nuclei-config
- Results bucket: gs://<client_name>-security-scans
- Scanner SA: <client_name>-nuclei-scanner@<project>.iam.gserviceaccount.com
- (if scheduler) Cloud Scheduler: <client_name>-nuclei-monthly (next run: <cron>)
- (if wif) WIF pool: <client_name>-ci-pool
- (if ar_mirror) Artifact Registry: <region>-docker.pkg.dev/<project>/<client_name>-nuclei

**Next steps:**
1. Verify the scanner SA has been granted the required roles listed during bootstrap.
2. Trigger the first scan manually:
   gcloud run jobs execute <client_name>-nuclei-scan --region=<region> --project=<gcp_project_id>
3. Monitor results in gs://<client_name>-security-scans/nuclei/
4. (if enable_ar_mirror) Push the scanner image to the AR repo manually,
   then update scanner_image in deployment.yaml to the AR URI and re-deploy.
```

---

## Error handling reference

| Failure | When | Action |
|---|---|---|
| YAML validation failure | Step 3 | Print field path + error; stop; do not make any cloud calls |
| `gcloud auth` missing or expired | Step 4 or 6 | Instruct `gcloud auth login` + `gcloud auth application-default login`; stop |
| `terraform` not installed | Step 6 | Print install link; stop |
| Bootstrap script failure | Step 4 | Surface gcloud error verbatim; check project ID and auth; stop |
| `terraform init` failure | Step 6 | Diagnose: bucket missing (re-run bootstrap), module path wrong (check CWD), auth error |
| `terraform plan` failure | Step 7 | Surface full error; check IAM grants from bootstrap output and API enablement |
| `terraform apply` failure | Step 10 | Surface full error; warn about partial state; advise `terraform show` before retry |

---

## Idempotency

Re-running the skill against the same `deployment.yaml`:
- Steps 3–5 always re-validate and re-render; generated files are overwritten, not appended.
- `terraform apply` on an unchanged YAML produces a zero-change plan.
- The operator must still confirm in step 9, even for a zero-change plan.

---

## Out of scope

This skill does not:
- Trigger the first scan after apply (operator does this manually via `gcloud run jobs execute`)
- Verify JSONL output or CSFLite control mappings
- Build or push the scanner image (produced by `.github/workflows/publish-image.yaml`)
- Modify the `infra/gcp/` Terraform module
- Deploy to AWS or Azure
- Provide a CLI program with argument parsing and exit codes
- Back up or sync `deployment.yaml` or `targets.txt`
- Provision the GCP project itself (assumes the project exists with appropriate IAM)
