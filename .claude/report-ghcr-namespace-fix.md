# Report — GHCR namespace fix (`leansecurity` → `eriklacson`)

**Date:** 2026-06-03
**Branch:** `component/gcp-deploy`
**Commit:** `b93b9a0` — `fix: correct GHCR namespace to repo owner (leansecurity -> eriklacson)`
**Tag:** `v1.0.0` (annotated, local only — points at `b93b9a0`)
**Plan:** [`.claude/plan.md`](plan.md) · **Investigation:** [`.claude/report.md`](report.md)

---

## TL;DR

The scanner image was published to the `ghcr.io/leansecurity/*` namespace, but the repo is owned
by the personal account `eriklacson`. GHCR packages live under the **repo owner's** namespace, and
`GITHUB_TOKEN` can only push there — so pushes to `leansecurity/*` were `denied` and the package was
never created. Consumers pulling `ghcr.io/leansecurity/leansec-nuclei` got **not found**.

Fixed by reverting the namespace to `eriklacson` across all operative and consumer-facing files
(decision confirmed by architect over the alternatives of creating a `leansecurity` org or using
`${{ github.repository }}`). Committed and tagged locally. **Not pushed** — that is the architect's.

---

## What changed

Three distinct "not found" defects were fixed in one pass:

| # | Defect | Before | After |
|---|---|---|---|
| 1 | GHCR image namespace | `ghcr.io/leansecurity/leansec-nuclei` | `ghcr.io/eriklacson/leansec-nuclei` |
| 2 | Terraform module source repo | `github.com/leansecurity/leansecurity-nuclei` (doubled name, non-existent) | `github.com/eriklacson/leansec-nuclei` |
| 3 | Package-page URLs | `github.com/orgs/leansecurity/packages/container/package/nuclei-scanner` (org doesn't exist; pre-rename package name) | `github.com/users/eriklacson/packages/container/package/leansec-nuclei` |

### Phase 1 — Operative (required for the package to exist & resolve)

| File | Change |
|---|---|
| `.github/workflows/publish-image.yaml` | `IMAGE_NAME: eriklacson/leansec-nuclei` |
| `infra/gcp/variables.tf` | `scanner_image` default → `ghcr.io/eriklacson/leansec-nuclei:latest` |
| `deployments/_example/terraform.tfvars` | → `ghcr.io/eriklacson/leansec-nuclei:v1.0.0` |
| `deployments/_example/main.tf` | module `source` → `github.com/eriklacson/leansec-nuclei.git//infra/gcp?ref=v1.0.0`; default image → `eriklacson` |
| `scripts/bootstrap-gcp-client.sh` | next-steps example image → `eriklacson` |

### Phase 2 — Documentation consistency

| File | Change |
|---|---|
| `README.md` | GHCR pull URLs + in-block local build tags → `eriklacson` |
| `docs/release.md` | GHCR URLs; package-page URLs (×2); reworded "Manage Actions access" step to note personal-account auto-linking |
| `docs/gcp_architecture.md` | GHCR image references (prose, mermaid node, tag list) |
| `docs/setup-guide.md` | GHCR image references (tfvars examples, troubleshooting link) |
| `infra/gcp/README.md` | `scanner_image` default + example; module `source` URL |

### Tag

`v1.0.0` annotated tag created on `b93b9a0`. This establishes the ref that
`deployments/_example/main.tf` and `infra/gcp/README.md` pin via the module `source`
(`?ref=v1.0.0`) and that the `scanner_image:v1.0.0` examples reference. No tag existed before.

---

## Verification

| Gate | Result |
|---|---|
| Residual `ghcr.io/leansecurity` in operative/consumer files | **0** (grep) |
| Residual `leansecurity/leansecurity-nuclei` module source | **0** |
| Residual `orgs/leansecurity` package URL | **0** |
| New `ghcr.io/eriklacson/leansec-nuclei` refs present | 11 files |
| Pre-commit hook | pytest **Passed**; black/ruff/bandit skipped (no Python files in diff) |

**Could not run** — tooling not installed in this environment: `terraform fmt -check`,
`terraform validate`, `actionlint`, `shellcheck`. All edits are value-only string substitutions
inside existing literals, so HCL/YAML/bash structure is unchanged — but this was **not**
machine-verified. Re-run these locally where the tools exist before relying on the release.

### Intentionally left (per plan scope boundary — not namespace problems)

- Project-name prose `leansecurity-nuclei` and state-bucket suffix `*-tfstate-leansecurity-nuclei`
  (brand string, not a GHCR owner).
- Local-only build tags `leansecurity/leansec-nuclei:local` / `:test-local` in `CLAUDE.md`,
  `tests/test_container.py`, `tests/validation/README.md` (never pushed to GHCR).
- `report-gcp-cloud-deploy.md` and `.claude/` planning artifacts (historical/meta).

---

## Outstanding — architect-only (cannot be done from the repo)

1. **Confirm the `v1.0.0` commit survives the merge to `main`.** The commit + tag are on
   `component/gcp-deploy`. The module `?ref=v1.0.0` resolves against the **remote**. If the branch
   is **squash-merged**, the tagged commit `b93b9a0` will not be in `main`'s history — move the tag
   to the post-merge commit before pushing. A real merge / fast-forward preserves it.
2. **Push** the branch and the tag: `git push origin <branch>` and `git push origin v1.0.0`.
   (Both deliberately left undone — repo prohibition on pushing.)
3. **Trigger a publish.** The workflow path filter fires only on `docker/**` / `scanner/**`
   changes; this commit touches neither, so use **Actions → Publish Scanner Image → Run workflow**
   (`workflow_dispatch` is wired). Pushing the `v1.0.0` tag also triggers the semver build.
4. **Confirm prior run status** in the Actions tab: no run (path filter) vs. red run (the `denied`
   push now fixed).
5. **First successful push creates a private package.** Make it public:
   `https://github.com/users/eriklacson/packages/container/package/leansec-nuclei`
   → Package settings → Danger Zone → Change visibility → Public.
6. **Verify anonymously:** `docker pull ghcr.io/eriklacson/leansec-nuclei:v1.0.0` (no auth prompt).

---

## Risks / watchpoints carried forward

1. **`?ref=v1.0.0` only resolves once the tag is pushed** to `eriklacson/leansec-nuclei`. Until
   then, a consumer `terraform init` fails on module download — by design, pending step 2 above.
2. **Provider/lint gates unverified** (tooling absent here) — see Verification note.
3. **Future `leansecurity` org migration** (if it happens): reverse the rename, transfer/recreate
   the GHCR package under the org, and bump consumers' `scanner_image` pins + module `?ref`.
   Setting `IMAGE_NAME: ${{ github.repository }}` would automate the workflow side of that
   transition — considered and not chosen now.

---

## Phase 3 (optional, not done)

Local build tags and project-name/bucket prose still read `leansecurity`. No effect on package
resolution. Apply only if full cosmetic consistency is wanted; if local tags are renamed, re-run
`pytest tests/test_container.py` since the image-tag constant changes.
