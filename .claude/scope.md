# Scope — gha-config-sync-private-repo

Source: `.claude/tasks/gha-config-sync-private-repo.md` ("Plan: GitHub Actions Config Sync via
Per-Client Private Repo (Option C)"). Read per CLAUDE.md execution loop step 1 (READ).

## 1. What the task file asks for

Move config sync (`targets.txt`, `profiles.yaml` → GCS) and `terraform apply` out of the
operator's local machine and into GitHub Actions running inside a **new, per-client private
repo** (`leansec-nuclei-<client>`). That repo holds the client's `deployment.yaml`,
`targets.txt`, `profiles.yaml`, and its own `.github/workflows/{deploy,plan}.yml`. It
references this repo's `infra/gcp` module by a version-pinned git ref, not a relative path.
The `gcp-deploy` skill remains for first-time bootstrap only; all later changes go through
PR → merge on the client repo.

The task file is itself already a plan (Phases 1–4) and explicitly lists 5 "open questions
(resolve before implementation)". Per CLAUDE.md, this task cannot proceed to IMPLEMENT until
those are resolved and the architect approves.

## 2. Current state (verified against the repo, not assumed from the task file)

- **Documented architecture says single-repo.** `.claude/docs/LeanSecurity_Nuclei_seed_document.md:17`:
  "The client's deployment lives under `deployments/<client>/` in the repository. The client
  does not own or modify the scanner, infrastructure modules, or CI/CD workflows." The
  per-client-private-repo model is a direct architectural change from what's documented, not
  an additive feature. No ADR exists for it yet (`decisions/` has only ADR-007, about the
  Python/bash split in the container — unrelated).
- **The `gcp-deploy` skill (merged, PR #16) already implements the in-repo model.** It
  resolves the module via **relative path** `../../infra/gcp` (`.claude/skills/gcp-deploy/SKILL.md`
  step 3/6), assumes the operator is at `deployments/<client>/` inside this repo checkout, and
  already has a **Step 10b** (GCS sync of `targets.txt`/`profiles.yaml`, added in `40f07c0`)
  and a **Step 11** (report results) — the exact steps Phase 2 and Phase 4 of this task target.
  Phase 1's proposed `main.tf` for the client-repo-template uses a **git-ref module source**
  instead — a legitimate difference (an external repo has no local checkout of `infra/gcp` to
  point a relative path at), not a bug, but it means two divergent `main.tf` template styles
  will exist in this repo for two different deployment topologies. This needs to be
  documented clearly so operators don't confuse them.
- **`infra/gcp/workflows/deploy.yml` and `infra/gcp/workflows/scanner-image.yml` do not
  exist**, despite being referenced as "Complete" in both CLAUDE.md and the seed document's
  file table. Only `.github/workflows/ci.yaml` and `.github/workflows/publish-image.yaml`
  exist. There is no existing in-repo `deploy.yml`/`plan.yml` to use as a starting point for
  Phase 2 — it would be built from scratch, in a different repo, with no precedent to check
  against.
- **WIF is already implemented in the Terraform module** (`infra/gcp/main.tf:168-204`,
  `variables.tf:88-108`) and gated by `enable_wif` + `wif_github_repository` (a
  `owner/repo` string bound into the IAM principal set). **Blocking gap:** the skill's
  `deployment.yaml` schema (`.claude/skills/gcp-deploy/schema/deployment.schema.json`)
  exposes `features.enable_wif` but has **no field for `wif_github_repository`** anywhere in
  schema, example YAML, or SKILL.md prompts. The tfvars template renders
  `wif_github_repository = "{{wif_github_repository}}"` but nothing in the current skill
  workflow ever collects that value from the operator. This directly blocks Phase 3 step 1
  of the new task ("operator runs gcp-deploy skill locally... Enable WIF") — there is
  currently no way to actually populate the value the WIF trust binding depends on.
- **Sequencing conflict in Phase 3 as written.** Step 1 says "enable WIF" during the local
  bootstrap apply, *then* step 2 says "create the private client repo." But
  `wif_github_repository` is exactly the client repo's `owner/repo` name — it must be known
  *before* the apply that provisions the WIF trust binding. As written, step 1 can't populate
  the value step 2 hasn't created yet. (This is open question #3 in the task file, and the
  gap above confirms it's a real blocker, not a hypothetical.)

## 3. What does NOT change (per task file, confirmed no conflict with current repo)

- `scanner/`, `docker/`, `ci.yaml`, `publish-image.yaml` — task file explicitly excludes these.
- The `infra/gcp` Terraform module itself (consumed by reference, not modified).
- The existing `deployments/<client>/` in-repo model — this task adds a second topology, it
  doesn't say it replaces the first (though the seed document's "lives under `deployments/<client>/`"
  line would become inaccurate for clients on the new model — a docs update, not a code one).

## 4. Open questions — resolved (see .claude/plan.md for full answers)

All 5 questions from the task file plus 2 found during this READ pass were resolved by the
architect on 2026-07-02: repos are client-owned (forked/copied into the client's own GitHub
account, not `eriklacson` or a shared org); access control is client-operated post-bootstrap;
module pinned by semver tag; plan PR comments collapsed via `<details>`; WIF ordering fixed by
creating the client repo before the local bootstrap runs; the `wif_github_repository` schema
gap is fixed as part of this task; ADR-008 is written before Phase 1 file creation.
