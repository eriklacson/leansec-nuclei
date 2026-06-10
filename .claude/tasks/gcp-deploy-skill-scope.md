# Scope — gcp-deploy Claude Code skill

Source spec: `.claude/tasks/gcp-deploy-skill-project.md` (feature `gcp-deploy-skill`, v1, 2026-05-22)
Read per CLAUDE.md execution loop step 1 (READ). Predecessor feature `gcp-cloud-deploy` verified merged (see "Predecessor check" below).

## 1. What we're building

A **Claude Code skill** — not a CLI program — that orchestrates GCP deployment of the
leansec-nuclei pipeline. It is a runbook (`SKILL.md`) that Claude Code interprets, plus
supporting schema/templates/example/command. It ships in the public repo at
`.claude/skills/gcp-deploy/` and is invoked by a technical operator from their private
deployment folder.

The skill's job, end to end:
1. Read a high-level `deployment.yaml` from the operator's deployment folder.
2. Validate it against a JSON schema (fail fast on bad input, before any cloud call).
3. Render Terraform `terraform.tfvars`, `main.tf`, `backend.tf` from the YAML.
4. Run `scripts/bootstrap-gcp-client.sh` (existing — invoked, not reimplemented).
5. Run `terraform init` + `terraform plan`.
6. Summarize the plan in chat, flagging IAM bindings / public bucket policies /
   destructive changes prominently.
7. **Wait for explicit operator confirmation**, then run `terraform apply`.
8. Report what was deployed and next steps.

Invocation: both intent-triggered ("deploy this to GCP") and the `/gcp-deploy` slash command.

## 2. Core principles / constraints

- **Runbook, not CLI.** Primary deliverable is natural-language `SKILL.md`. No argument
  parser, no exit codes, no `scripts/deploy.sh`.
- **Operator-in-the-loop for apply.** Never `terraform apply` without an unambiguous
  affirmative in chat.
- **Validate before cloud calls.** Schema check gates all gcloud/terraform work.
- **Idempotent re-runs.** All generated files (tfvars, backend.tf, main.tf) are
  re-rendered/overwritten each run with "regenerated — do not edit" headers; never appended.
- **No client artifacts in the skill.** Only placeholders (`<your-client>`,
  `<your-gcp-project>`, `example.com`). Skill never writes to `deployments/_example/`.
- **Module consumed as-is.** No changes to `infra/gcp/`. If the module needs changes,
  that's a separate feature.
- **No module version pinning in YAML.** Skill uses the module shipping in the same repo
  checkout, resolved by relative path `../../infra/gcp`.

## 3. Deliverables

### Workstream B — Build (no deps)
| ID | File | Notes |
|---|---|---|
| B1 | `.claude/skills/gcp-deploy/SKILL.md` | 11 numbered workflow steps; per-step success/failure clauses; error handling for 7 failure modes; relative module path `../../infra/gcp`; named constant for default scanner image; operator-in-the-loop rule. |
| B2 | `.claude/skills/gcp-deploy/schema/deployment.schema.json` | JSON Schema draft-07+, `additionalProperties:false` everywhere. Groups: `deployment`, `scanner`, `features`, `schedule`, `targets` + `schema_version`. |
| B3 | `.claude/skills/gcp-deploy/templates/deployment.example.yaml` | Annotated, every schema field present, placeholders only, validates against B2. |
| B4 | `.claude/skills/gcp-deploy/templates/tfvars.tmpl` | Covers **every** var in `infra/gcp/variables.tf`. Rendered output passes `terraform fmt -check` + `validate`. |
| B5 | `.claude/skills/gcp-deploy/templates/main.tf.tmpl` + `backend.tf.tmpl` | `main.tf` module source = relative `../../infra/gcp`; backend bucket = `<project>-tfstate-leansecurity-nuclei`. |
| B6 | `.claude/commands/gcp-deploy.md` | Thin slash-command wrapper invoking the skill against CWD. Verify current Claude Code command convention at impl time. |
| B7 | `.gitignore` | **Already largely satisfied** — see Discrepancy #3. |
| B8 | `.claude/skills/gcp-deploy/README.md` | Human-facing; purpose, invocation, prereqs, file layout, workflow overview, out-of-scope, cross-links. |

### Workstream D — Documentation (depends on B)
| ID | File | Notes |
|---|---|---|
| D1 | `README.md` | Add "Skill-assisted deployment" subsection under cloud mode; both invocation paths; cross-links. |
| D2 | `docs/setup-guide.md` | Add "Quick start: using the gcp-deploy skill" at top (recommended); demote existing manual path to "Manual setup (alternative)". |
| D3 | `docs/gcp_architecture.md` | One paragraph: skill is an automation layer over the same module, not a change to architecture. |

Sequencing: **build → documentation** (docs must reference the final shape).

## 4. YAML schema shape (B2 target)

```
schema_version: 1                      # int, enum[1], required
deployment:
  client_name:    ^[a-z][a-z0-9-]{1,30}$   required
  gcp_project_id: ^[a-z][a-z0-9-]{5,29}$   required
  region:         default asia-southeast1
scanner:
  image:          full URI w/ tag; omit -> skill default
features:
  enable_scheduler: bool, default true
  enable_wif:       bool, default false
  enable_ar_mirror: bool, default false
schedule:
  cron:     default "0 2 1-7 * 0"
  timezone: default Etc/UTC
targets:
  file:     default ./targets.txt
```

## 5. Predecessor check (gcp-cloud-deploy) — PASS

All required artifacts present in the current checkout:
- `infra/gcp/` module with `enable_scheduler`, `enable_wif`, `enable_ar_mirror` flags ✓
- `scripts/bootstrap-gcp-client.sh` ✓ (state bucket `<project>-tfstate-leansecurity-nuclei`)
- `deployments/_example/` (GHCR-model tfvars) ✓
- `docs/setup-guide.md`, `docs/gcp_architecture.md` ✓
- `.github/workflows/publish-image.yaml` ✓

## 6. Discrepancies between spec and current repo — MUST resolve in PLAN

1. **Default scanner image registry path is stale in the spec.**
   Spec (`scanner_image_default`, B-content) names `ghcr.io/leansecurity/nuclei-scanner`.
   Actual: `infra/gcp/variables.tf` default is `ghcr.io/eriklacson/leansec-nuclei:latest`,
   and recent commits (`b93b9a0`, `ab0d275`) deliberately set the GHCR namespace to
   `eriklacson` and image name to `leansec-nuclei`. **Use the actual repo value**
   (`ghcr.io/eriklacson/leansec-nuclei:<tag>`) as the baked-in default, not the spec string.

2. **Module source: relative path vs git ref.**
   Spec decision `module_version_pinning` + B5 mandate `source = "../../infra/gcp"` (relative).
   Existing `deployments/_example/main.tf` uses `git::https://...//infra/gcp?ref=v1.0.0`.
   These are two different distribution models. The skill follows the spec (relative path),
   which means the skill-rendered `main.tf` will intentionally differ from the current
   `_example/main.tf`. Confirm with architect that the relative-path model is intended for
   skill-rendered deployments (it requires the operator folder to sit at `deployments/<client>/`
   inside the repo checkout, which decision `deployment_folder_location` already assumes).

3. **B7 (.gitignore) is already mostly done.**
   `.gitignore` already contains `deployments/*`, `!deployments/_example/`, plus an extra
   `!deployments/_validation/`. Spec also wants `!deployments/_example/**`. Net work for B7
   is at most adding the `/**` recursive re-include; verify the acceptance behavior
   (ignored under `deployments/foo/`, tracked under `deployments/_example/`) still holds.

4. **tfvars scope is wider than the current example.**
   Current `deployments/_example/terraform.tfvars` only sets `project_id`, `client_name`,
   `scanner_image`; `targets_file`/`profiles_file` are wired in `main.tf` via `path.module`.
   B4 requires the template to cover every `variables.tf` variable. Decide which the skill
   renders into tfvars vs hardcodes in the rendered `main.tf` (e.g. `targets_file`,
   `profiles_file` paths). YAML `targets.file` maps to module `targets_file`.

## 7. Out of scope (do not build)

First-scan trigger; JSONL output verification; image build/push; module changes;
multi-cloud abstraction; CLI program / `scripts/deploy.sh`; backup/sync of intent files;
reimplementing the bootstrap script; GCP project provisioning.

## 8. Verification demarcation

- **Claude-verifiable locally:** file existence, JSON-schema validity (self/meta + sample
  YAMLs), markdown lint, template substitution dry-run against `deployment.example.yaml`,
  `terraform fmt/validate` on rendered output, `.gitignore` behavior.
- **Architect-verified (needs real GCP):** end-to-end skill run — scaffold, render, plan
  summary quality, confirm-then-apply, idempotent re-run (zero diff), flag-flip delta,
  `/gcp-deploy` reaches same behavior.

## Open questions for architect (PLAN gate)

- Confirm discrepancy #1 (image default = `ghcr.io/eriklacson/leansec-nuclei`) and #2
  (relative module source for skill-rendered deployments).
- Decide field-by-field tfvars vs rendered-main.tf placement (#4).
- Confirm the default image **tag** to bake in (latest semver released by publish-image).
