# Scope — gcp-cloud-deploy

Source: `.claude/docs/project.yaml` (feature: `gcp-cloud-deploy`, mode: build, v1, 2026-05-22).

## Objective

Activate the GCP Cloud Automated deployment tier of `leansecurity-nuclei`. The Terraform module, container entrypoint, and gated CI workflows exist as scaffolding but have never been validated end-to-end. This feature:

1. Rewrites the GCP module to support a **public-repo / private-deployments** topology with optional flags.
2. Publishes the scanner image to **GHCR** (`ghcr.io/leansecurity/leansec-nuclei`) as the canonical distribution channel.
3. Fixes two known defects (Terraform env block formatting; entrypoint↔profiles drift).
4. Ships an architect-driven onboarding runbook (bootstrap script + setup guide).
5. Produces consumer-facing documentation for the open-source release.

LeanSecurity owns no GCP infrastructure. `terraform apply` runs from the architect's workstation; Cloud Scheduler is the autonomous loop after deployment.

## Operating model (locked decisions)

- Public repo holds the reusable pipeline + module. Per-client deployment configuration lives in client-controlled storage outside this repo.
- Scanner image is distributed via GHCR. Clients pull from GHCR directly, or mirror into their own Artifact Registry.
- Public-repo CI does not hold GCP credentials and never touches client infra. Cloud-side execution is architect-driven.

## Workstreams (sequential)

Sequencing is strict: `build → documentation → setup-guide`. Each workstream's `workstream_acceptance` must pass before the next begins.

### B. Build (8 deliverables)

| ID | Title | Type | Files (primary) |
|----|-------|------|-----------------|
| B1 | Fix Terraform env block formatting | fix | `infra/gcp/main.tf` |
| B2 | Fix profiles.yaml ↔ entrypoint.sh drift | fix | `docker/entrypoint.sh` (see open question below) |
| B3 | Rewrite `infra/gcp/` Terraform module | rewrite | `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (new) |
| B4 | Delete `infra/gcp/workflows/deploy.yml` | delete | `infra/gcp/workflows/deploy.yml` |
| B5 | Replace scanner-image.yml with `publish-image.yaml` | replace | `.github/workflows/publish-image.yaml` (new), delete `infra/gcp/workflows/scanner-image.yml` |
| B6 | Write `scripts/bootstrap-gcp-client.sh` | new | `scripts/bootstrap-gcp-client.sh` (new dir) |
| B7 | Refresh `deployments/_example/` | update | `_example/main.tf`, `terraform.tfvars`, `backend.tf`, `targets.txt`, `README.md` |
| B8 | Remove `deployments/mdi/` placeholder | delete | `deployments/mdi/`, `.gitignore` edit |

New module variables (B3): `enable_scheduler` (default `true`), `enable_wif` (default `false`), `enable_ar_mirror` (default `false`). Preserved required-variable interface: `project_id`, `client_name`, `scanner_image`, `targets_file`. Preserved outputs: `config_bucket_name`, `results_bucket_name`, `cloud_run_job_name`, `scheduler_job_name` (null when scheduler disabled), `scanner_service_account_email`.

New workflow (B5) publishes three tags per build: `:latest` (main HEAD), `:<short-sha>` (every build), `:vX.Y.Z` (on tag push). Auth via built-in `GITHUB_TOKEN`. Triggers: push to `main` on `docker/**` or `scanner/**` paths; push of `v*` tags.

### D. Documentation (3 deliverables)

| ID | Title | Files |
|----|-------|-------|
| D1 | Update root `README.md` (remove "not yet available", add cloud section + cross-links) | `README.md` |
| D2 | Write module reference `infra/gcp/README.md` | `infra/gcp/README.md` |
| D3 | Distill architecture brief into `docs/gcp_architecture.md` | `docs/gcp_architecture.md` (new dir), source: `.claude/docs/gcp-cloud-deploy-brief.html` |

Implicit doc deliverable (per `decisions_to_confirm.seed_document_locked_decisions`): append three locked design decisions verbatim to `.claude/docs/LeanSecurity_Nuclei_seed_document.md`.

### S. Setup Guide (1 deliverable)

| ID | Title | Files |
|----|-------|-------|
| S1 | Write `docs/setup-guide.md` (end-to-end open-source onboarding) | `docs/setup-guide.md` |

Required: 11 ordered steps from prerequisites through first-scan verification, plus an Ongoing Operations section and a Troubleshooting section covering 5 specified failure modes (API not enabled, IAM denied, state bucket access denied, image pull failure, Cloud Run timeout).

## Constraints (feature-wide, blocking)

- **No client artifacts in repo.** Only `deployments/_example/` is permitted as a deployment-shaped folder, with placeholders only.
- **Scanner layer unchanged.** No edits to `scanner/scan.py`, `scanner/nuclei_helpers.py`, or `tests/`, except B2's profile-name drift fix.
- **Progressive deployment preserved.** Local CLI mode (`poetry run python scanner/scan.py <client>`) must continue to work; validate before any `docker/` or `infra/` commit.
- **Entrypoint stays bash.** No Python dependency, no YAML parsing, no `scan.py` invocation logic added beyond what already exists.
- **Terraform module parameterized.** No hardcoded client names, project IDs, region, bucket names, or image paths in `infra/gcp/`.
- **Code-ready scope only.** Acceptance items marked `verified_by: architect` are NOT to be run by Claude Code (B5 first GHCR push, B6 against real GCP, S1 end-to-end walkthrough, brief §9 items 4-13).

## Verification gates (Claude-runnable)

- `poetry run black --check . && poetry run ruff check . && poetry run bandit -r . --severity-level high && poetry run pytest`
- `terraform validate` and `terraform fmt -check` on `infra/gcp/`
- `actionlint .github/workflows/*.yaml`
- `shellcheck` on `scripts/*.sh` and `docker/*.sh`
- Local CLI + Local Docker (`CLOUD_PROVIDER=local`) modes still produce correctly-named JSONL

## Inputs required

- `.claude/docs/gcp-cloud-deploy-brief.html` — already present in working tree; source for D3.
- Current repository state.

## Explicit out of scope

- Onboarding any real paying client.
- AWS/Azure module work (remain stubbed).
- Any scanner-layer change beyond B2.
- Cloud-side validation against a real client GCP project.
- Conduit ingestion validation.
- Sync tooling between private storage and architect workstation.
- LeanSecurity-internal operations runbook (lives in private docs).
- SLO tracking component / web UI / future components.

## Open questions / discrepancies surfaced during READ

These need architect confirmation before PLAN is finalized.

1. **B2 may already be resolved.** The current `docker/entrypoint.sh` does not contain hardcoded `nuclei` invocations — it delegates to `python /app/scanner/scan.py "${CLIENT}"`. The "drift" described in B2 (entrypoint writes `identity_*.jsonl` / `transport_*.jsonl` / `owasp_top10_*.jsonl`) is not present in the file as it stands. `scanner/profiles/profiles.yaml` `output:` fields already match the profile keys exactly (`identity_remote_access.jsonl`, `transport_security.jsonl`, `owasp_top10_core.jsonl`). **Proposed action:** treat B2 as a verification deliverable — re-run local Docker mode end-to-end, confirm output filenames match profile keys, document the confirmation. If true, B2 collapses to a no-op acceptance check. Confirm.

2. **`.gitignore` actually ignores all `deployments/`, not just `deployments/mdi/`.** Current line is `deployments/` (line 11). B8 says "remove the `deployments/mdi/` line" — that line does not exist. The blanket `deployments/` ignore also contradicts the CI auto-discovery model and the requirement that `deployments/_example/` is tracked (it currently is tracked, presumably via `git add -f` history). **Proposed action:** either (a) replace `deployments/` with explicit ignores for `*.tfstate*`, `.terraform/`, etc. inside deployment folders while allowing tracked files through, or (b) replace with `deployments/*` + `!deployments/_example/`. Recommend (b) for minimal blast radius. Confirm direction.

3. **`infra/gcp/main.tf` env blocks** — the project.yaml describes them as "malformed" and "RESULTS_BUCKET env value appears truncated." Inspection shows they are syntactically single-line `env { name = "X" value = "Y" }` blocks (lines 101-105). They will fail `terraform fmt` and may not parse cleanly under the v6+ provider schema, but they are not literally truncated. **Proposed action:** rewrite as multi-line blocks per the brief; treat the "truncated" phrasing as descriptive of fmt drift rather than literal data loss. Confirm.

4. **B7's existing `_example/README.md`** — already exists in the working tree (project.yaml lists "create if absent"). **Proposed action:** refresh, not create. Confirm.

5. **`docs/` directory does not exist** — D3 and S1 both target `docs/`. **Proposed action:** create on first write; no architect input needed unless a different location is desired.

6. **Decisions to confirm (per `decisions_to_confirm` block)** — all six recommended defaults (image tag scheme, GHCR image name, bootstrap delivery as bash, deleting old scanner-image.yml, AR mirror flag default off, seed-document locked decisions) need explicit architect confirmation before PLAN proceeds.
