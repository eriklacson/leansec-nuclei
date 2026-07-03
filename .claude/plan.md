# Plan — gha-config-sync-private-repo

Status: **approved 2026-07-02.** Architect answers below; implementation proceeds per this plan.

## Architect decisions (2026-07-02)

- **Repo ownership (open question #1):** client-owned/forked. Each client forks or copies
  `client-repo-template/` into their **own** GitHub account — not `eriklacson` and not a
  shared `leansec-clients` org. There is no centrally-owned client repo.
- **Access control (open question #5):** client pushes to their own repo and operates it
  independently once bootstrapped. This is a real change from the seed document's stated
  "the client does not own or modify... CI/CD workflows" (`LeanSecurity_Nuclei_seed_document.md:17`)
  — the ADR (task below) must say so explicitly, since it's the architectural point this whole
  task changes.
- **Plan approved as written**, including: ADR-008, the `wif_github_repository` schema fix,
  and the corrected Phase 3 ordering (client repo must exist before local WIF bootstrap runs,
  since `wif_github_repository` is that repo's `owner/repo`).

Consequence for Phase 3 sequencing: since the client owns the repo, "operator" in the
task file's Phase 3 splits into two roles — the **architect** (runs local GCP bootstrap,
provisions the WIF trust binding, hands off `terraform output` values) and the **client**
(creates their own repo, receives the WIF provider/SA values, sets them as repo variables,
pushes the template). Step 5 below reflects this.

## Recommended sequencing (subject to answers below)

1. **ADR first.** Add `decisions/ADR-008-per-client-repo-topology.md` recording that
   per-client private repos are an intentional second deployment topology alongside the
   documented `deployments/<client>/` in-repo model — not a replacement. Update the one
   sentence in the seed document (`.claude/docs/LeanSecurity_Nuclei_seed_document.md:17`)
   that currently states the in-repo model as if it's the only one.
2. **Close the WIF schema gap** (found in scope.md §2) before Phase 3 can work at all:
   add `features.wif_github_repository` (string, required when `enable_wif: true`) to
   `deployment.schema.json`, `deployment.example.yaml`, and a SKILL.md prompt step. Without
   this, "enable WIF" in Phase 3 step 1 has no value to bind.
3. **Phase 1 — `infra/gcp/client-repo-template/`** as specified in the task file, with the
   git-ref module source (this is correct for an external repo — no relative path is
   possible). Add a header comment in its `main.tf` clarifying it's for the *external private
   repo* topology, distinct from `infra/gcp/_example/` (used by the skill for the *in-repo*
   topology), so the two don't get confused later.
4. **Phase 2 — `deploy.yml` / `plan.yml`** inside the template, built from scratch (no
   existing precedent — `infra/gcp/workflows/deploy.yml` referenced in CLAUDE.md/seed doc
   does not exist on disk).
5. **Phase 3 — bootstrap sequencing, corrected order (client-owned repo model):**
   a. **Client** creates their own private repo first (`gh repo create leansec-nuclei-<client> --private`,
      under their own account — not the architect's).
   b. Client tells the architect the repo's `owner/repo` name.
   c. **Architect** runs the gcp-deploy skill locally with `enable_wif: true` and
      `wif_github_repository: <client-owner>/leansec-nuclei-<client>` now populated (closes
      the ordering conflict — the repo exists before the value that names it is bound into
      the WIF trust policy).
   d. Architect hands the client the WIF provider resource name, SA email, project ID,
      region, and client name from `terraform output` (SKILL.md Step 11, Phase 4 below).
   e. **Client** copies `client-repo-template/` contents into their repo, sets the 5 repo
      variables the architect gave them, and pushes.
   f. All future changes happen via PR → merge on the client's own repo — the client
      operates it independently from that point on.
6. **Phase 4 — amend SKILL.md Step 11** (report results) to print the `gh repo create` +
   `gh variable set` commands pre-filled from actual `terraform output` values, and note
   the corrected ordering from step 5 above.

## Answers (resolved 2026-07-02)

| # | Question | Decision |
|---|---|---|
| 1 | Repo ownership | Client-owned — their own GitHub account, not `eriklacson`, not a shared org. |
| 2 | Module pin: semver tag or commit SHA? | Semver tag (`?ref=vX.Y.Z`) — matches existing `scanner_image` tag conventions; no precedent for SHA pinning in this repo. |
| 3 | WIF bootstrap ordering | Client repo created first; architect runs local bootstrap second, once `wif_github_repository` is known (plan step 5). |
| 4 | `terraform plan` PR comment size | Collapsed in a `<details>` block via `actions/github-script`; summary line visible outside it. |
| 5 | Access control per client repo | Client pushes to their own repo and operates it independently post-bootstrap. |
| 6 | `wif_github_repository` schema gap | Fix now — Phase 3 is inert without it. |
| 7 | ADR now or later? | Now, before Phase 1 file creation — this task changes a documented architecture statement (seed doc §17), not just adds a feature. |

## Verification (once approved and built)

- `terraform validate` / `terraform fmt -check` on the rendered `client-repo-template/` files
  (cannot run `terraform plan` against real GCP from this environment — flagged as
  architect-verified).
- `deployment.schema.json` self-validates; updated `deployment.example.yaml` validates against it.
- `poetry run black --check . && poetry run ruff check . && poetry run bandit -r . -x ".venv,venv,build,dist,docs,migrations,tests" && poetry run pytest -q` — this task adds no Python, so expect no change in outcome, but run to confirm no regression.
- Manual review of `deploy.yml`/`plan.yml` YAML syntax (`yamllint` or GH Actions' own validation on push) — cannot dry-run GHA locally.
- End-to-end (`gh repo create`, WIF trust, real `terraform apply` from GHA) is **architect-verified only** — this environment has no GCP credentials or GitHub write access for a real client.

## Out of scope (per task file, unchanged)

- Migrating the existing `mdi` deployment to a client repo.
- AWS/Azure equivalents.
- Automated module version bumps across client repos.
- Any changes to `scanner/`, `docker/`, `ci.yaml`, `publish-image.yaml`.
