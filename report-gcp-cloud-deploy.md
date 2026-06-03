# Report — gcp-cloud-deploy

Companion to [`.claude/scope.md`](.claude/scope.md) and [`.claude/plan.md`](.claude/plan.md). Execution completed 2026-05-28.

## Deliverables — status

### Build (B)

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| B1 | Fix Terraform env block formatting | ✅ done | Cloud Run job env entries rewritten as multi-line blocks; provider bumped to `google ~> 6.0` (new [`versions.tf`](infra/gcp/versions.tf)). |
| B2 | Profiles.yaml ↔ entrypoint.sh drift | ✅ verified (no-op) | Static inspection confirms all 7 `profiles.yaml` `output:` stems equal their profile keys; `entrypoint.sh` delegates to `scan.py` (no hardcoded nuclei invocations beyond `-update-templates`); `scan.py` constructs filenames as `{stem}_{YYYY-MM}.jsonl`. Drift described in project.yaml is fully resolved in current code. |
| B3 | Rewrite `infra/gcp/` module | ✅ done | Added `enable_scheduler`, `enable_wif`, `enable_ar_mirror` variables; scheduler/WIF/AR-mirror resources behind `count`; `scheduler_job_name` returns null when disabled; new outputs for WIF/AR. `scanner_image` accepts any URI; default `ghcr.io/leansecurity/leansec-nuclei:latest`. |
| B4 | Delete `infra/gcp/workflows/deploy.yml` | ✅ done | `git rm`'d. |
| B5 | publish-image.yaml + delete scanner-image.yml | ✅ done | New [`.github/workflows/publish-image.yaml`](.github/workflows/publish-image.yaml) builds and pushes to GHCR with three-tag scheme via `docker/metadata-action@v5`. Old `scanner-image.yml` deleted. |
| B6 | `scripts/bootstrap-gcp-client.sh` | ✅ done | Idempotent bash; `set -euo pipefail`; shellcheck clean; `--help` exits 0; no-args exits 1 with usage. |
| B7 | Refresh `deployments/_example/` | ✅ done | `main.tf` calls module via git source ref pinned to `v1.0.0`; `tfvars`/`backend.tf`/`targets.txt`/`README.md` use placeholder values only. |
| B8 | Remove `deployments/mdi/` + fix `.gitignore` | ✅ done | mdi folder deleted; `.gitignore` rewritten to `deployments/*` + `!deployments/_example/` + `!deployments/_validation/`; removed broken negation lines (had stray spaces after `!`). `git check-ignore` confirms behavior. |

### Documentation (D)

| ID | Title | Status |
|----|-------|--------|
| D-pre | Three locked decisions appended to seed doc (`§10`); seed doc bumped to v1.4 with new changelog entry | ✅ done |
| D1 | Root `README.md` cloud section rewritten; "not yet available" removed; broken `.env.example` reference cleaned up; repo-structure block updated | ✅ done |
| D2 | [`infra/gcp/README.md`](infra/gcp/README.md) full module reference | ✅ done |
| D3 | [`docs/gcp_architecture.md`](docs/gcp_architecture.md); mermaid for both diagrams; §7–§10 of the brief omitted per scope | ✅ done |

### Setup guide (S)

| ID | Title | Status |
|----|-------|--------|
| S1 | [`docs/setup-guide.md`](docs/setup-guide.md); 11 ordered steps + Ongoing Operations + Troubleshooting (all 5 required failure modes covered) | ✅ done |

## Verification gate results

| Gate | Result |
|------|--------|
| `poetry run black --check .` | ✅ pass (10 files unchanged) |
| `poetry run ruff check .` | ✅ pass (all checks passed) |
| `poetry run bandit -r . --severity-level high` | ✅ pass (no high-severity findings) |
| `poetry run pytest` | ✅ pass (57 tests) |
| `shellcheck scripts/*.sh` | ✅ pass (0 findings) |
| `shellcheck docker/entrypoint.sh` | ⚠ pre-existing SC2295 info-level warning at line 82 — out of scope per `container_entrypoint_stays_bash` constraint |
| `terraform validate` / `terraform fmt -check` | ⚠ deferred — terraform not installed in the execution environment. Architect must run locally. |
| `actionlint .github/workflows/*.yaml` | ⚠ deferred — actionlint not installed. YAML parses with `python3 -c "import yaml"`. |

## Architect-verified items still outstanding

These items in the project.yaml are marked `verified_by: architect` and require real GCP credentials. Claude Code does not run them:

- **B5** — first successful image push to `ghcr.io/leansecurity/leansec-nuclei` from a real CI run.
- **B6** — `scripts/bootstrap-gcp-client.sh` executed against a fresh GCP test project.
- **S1** — end-to-end setup guide walkthrough against a fresh test GCP project producing a working deployment with no out-of-doc steps required.
- **Brief §9 items 4–13** — full cloud-side acceptance checklist (terraform init/plan/apply, manual scan, JSONL filename verification, scheduler state, flag-flip plans).

## Risks and watchpoints

1. **Provider version bump from `~> 5.0` to `~> 6.0`.** Required for the Cloud Run v2 job env-block schema fix in B1. If the architect prefers staying on v5, the multi-line env-block syntax remains valid on v5 as well — the bump can be rolled back in `versions.tf` without other module changes.

2. **`profiles_file` variable retained.** Per scope, the module still uploads `profiles.yaml` to the config bucket alongside `targets.txt`. The container also bakes profiles into the image at build time (per ADR-007), so the config-bucket copy is technically redundant. Keeping it preserves the current contract; removing it is a future cleanup, out of scope for this feature.

3. **`docker/entrypoint.sh` SC2295 info-level warning.** Pre-existing, untouched per `container_entrypoint_stays_bash` constraint. Fix is trivial (`"${results_dir}"` quoted separately inside the parameter expansion) when an architect-approved entrypoint touch is in scope.

4. **WIF supporting variables shape.** The module exposes `wif_github_repository` as the only WIF input. Non-GitHub OIDC issuers (GitLab, Azure DevOps, etc.) would require additional variables and a different attribute mapping. Out of scope for this revision; GitHub is the only mentioned consumer.

5. **`enable_ar_mirror` mirror push is manual.** The Terraform module only creates the empty AR repository. The architect must `docker pull` from GHCR, re-tag, and `docker push` to the AR before re-applying with `scanner_image` pointed at the AR URI. The setup guide's troubleshooting section documents this; the architect onboarding workflow should make it a labeled step if the flag is enabled.

6. **`_example/main.tf` source ref pins to `v1.0.0`.** The semver tag does not yet exist in the public repo. Architect must publish `v1.0.0` (or update the ref in the example) before the example is usable as documentation-by-example.

## Files changed

### New
- `infra/gcp/versions.tf`
- `.github/workflows/publish-image.yaml`
- `scripts/bootstrap-gcp-client.sh`
- `infra/gcp/README.md` (full rewrite from scaffold)
- `docs/gcp_architecture.md`
- `docs/setup-guide.md`
- `report-gcp-cloud-deploy.md` (this file)

### Modified
- `infra/gcp/main.tf` (B1 + B3)
- `infra/gcp/variables.tf` (B3)
- `infra/gcp/outputs.tf` (B3)
- `README.md` (D1)
- `deployments/_example/main.tf`, `terraform.tfvars`, `backend.tf`, `targets.txt`, `README.md` (B7)
- `.gitignore` (B8)
- `.claude/docs/LeanSecurity_Nuclei_seed_document.md` (D-pre)

### Deleted
- `infra/gcp/workflows/deploy.yml` (B4)
- `infra/gcp/workflows/scanner-image.yml` (B5)
- `deployments/mdi/{backend.tf,main.tf,targets.txt,terraform.tfvars}` (B8)

## Next steps for architect

1. Install terraform locally and run `terraform validate` + `terraform fmt -check` in `infra/gcp/`. Run `terraform plan` against a test project to confirm the resource shape under each flag combination (default, `enable_scheduler=false`, `enable_wif=true`, `enable_ar_mirror=true`).
2. Install actionlint and validate `.github/workflows/publish-image.yaml`. Push to a feature branch to trigger a real CI build and confirm GHCR push.
3. Run `scripts/bootstrap-gcp-client.sh` against a fresh test project.
4. Walk through `docs/setup-guide.md` end-to-end on the test project.
5. Tag the public repo `v1.0.0` (or update the source ref in `deployments/_example/main.tf` to whichever tag becomes canonical).
6. After verifying everything, merge the feature branch.
