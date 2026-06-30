# gcp-deploy skill

## Purpose

The `gcp-deploy` skill orchestrates a complete GCP deployment of the leansecurity-nuclei
pipeline from a single high-level configuration file (`deployment.yaml`). It validates
operator intent, renders Terraform inputs, runs the bootstrap script, presents a
human-readable plan summary, and applies only after explicit confirmation — all from a
Claude Code session.

## How to invoke

**Intent-triggered** — say any of the following in a Claude Code session:
- "deploy this to GCP"
- "run the GCP deployment"
- "apply the gcp-deploy skill"
- "set up the scanner on GCP"

**Slash command** — run `/gcp-deploy` from a Claude Code session in your deployment folder.

Both paths execute the same 11-step workflow.

## Prerequisites

| Requirement | Check |
|---|---|
| gcloud CLI | `gcloud version` + `gcloud auth list` shows active account |
| Terraform | `terraform version` |
| leansec-nuclei repo checkout | Operator folder at `deployments/<client>/` inside the repo |
| Python 3 | `python3 --version` (used for YAML validation; sed fallback available) |
| GCP project | Must exist; operator must have sufficient IAM (see bootstrap script output) |

## File layout

```
.claude/skills/gcp-deploy/
├── SKILL.md                         # Runbook — Claude Code reads and executes this
├── README.md                        # This file — for human operators
├── schema/
│   └── deployment.schema.json       # JSON Schema for deployment.yaml validation
└── templates/
    ├── deployment.example.yaml      # Annotated starting point for operators
    ├── tfvars.tmpl                  # Rendered into terraform.tfvars
    ├── main.tf.tmpl                 # Rendered into main.tf (module call)
    └── backend.tf.tmpl              # Rendered into backend.tf (GCS state)
```

The slash command entry point lives at `.claude/commands/gcp-deploy.md`.

## Configuration

Copy `templates/deployment.example.yaml` to your deployment folder as `deployment.yaml`
and populate all `<placeholder>` values. Required fields:

- `deployment.client_name` — short lowercase identifier (2-31 chars, `a-z 0-9 -`)
- `deployment.gcp_project_id` — GCP project ID (6-30 chars, `a-z 0-9 -`)

All other fields are optional with sensible defaults. See the annotated example for
every field with its purpose, valid values, and default.

## Workflow overview

The skill executes 11 steps:

1. **Detect folder state** — check for `deployment.yaml` in CWD
2. **Scaffold** (if needed) — copy `deployment.example.yaml`, prompt operator to populate, then stop
3. **Validate** — check `deployment.yaml` against the JSON schema; fail fast before any cloud calls
4. **Bootstrap** — run `scripts/bootstrap-gcp-client.sh` to enable APIs and create the state bucket
5. **Render Terraform files** — substitute YAML values into `tfvars.tmpl`, `main.tf.tmpl`, `backend.tf.tmpl`
6. **`terraform init`** — initialise the GCS backend and download the local module
7. **`terraform plan`** — generate and capture the plan
8. **Summarise plan** — present resource counts; call out IAM bindings and destructive changes prominently
9. **Confirm** — ask the operator for explicit approval before applying
10. **`terraform apply`** — only after step 9 confirmation
11. **Report** — list deployed resources and next steps (first scan trigger, AR mirror push if applicable)

## What this skill does not do

- Trigger the first scan after apply
- Verify JSONL output or CSFLite control mappings
- Build or push the scanner image (see `.github/workflows/publish-image.yaml`)
- Modify the `infra/gcp/` Terraform module
- Deploy to AWS or Azure
- Provision the GCP project itself

## See also

- [`docs/setup-guide.md`](../../docs/setup-guide.md) — full GCP setup walkthrough including manual path
- [`docs/gcp_architecture.md`](../../docs/gcp_architecture.md) — what the module deploys and why
- [`infra/gcp/README.md`](../../infra/gcp/README.md) — Terraform module reference
