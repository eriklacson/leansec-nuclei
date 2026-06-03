# Investigation Report — GHCR package "cannot be found"

**Date:** 2026-06-03
**Scope:** Read-only investigation. No code/config changed. This report only documents findings and a proposed fix.

---

## TL;DR

The publish pipeline pushes the scanner image to the **`leansecurity` GHCR namespace**, but this
repository is owned by the **personal account `eriklacson`** (`git@github.com:eriklacson/leansec-nuclei.git`).
GitHub Container Registry packages live under the *owner's* namespace, and the `GITHUB_TOKEN`
used by the workflow can only write packages under the repo owner's namespace
(`ghcr.io/eriklacson/*`). A push to `ghcr.io/leansecurity/...` is rejected (`denied`), so the
package is never created — hence consumers pulling `ghcr.io/leansecurity/leansec-nuclei`
get **not found**.

To ship under the personal repo, the image must be `ghcr.io/eriklacson/leansec-nuclei`, and all
references (workflow, Terraform defaults, docs, package-page URLs, module source URL) must follow.

---

## Evidence

### 1. Repository owner is a personal account
`.git/config`:
```
[remote "origin"]
    url = git@github.com:eriklacson/leansec-nuclei.git
```
Owner = `eriklacson` (user), repo = `leansec-nuclei`. There is no `leansecurity` org backing the namespace yet.

### 2. The workflow publishes to the wrong namespace
`.github/workflows/publish-image.yaml:18`:
```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: leansecurity/leansec-nuclei   # <-- wrong owner namespace
```
Login uses the repo-scoped token (`.github/workflows/publish-image.yaml:35-40`):
```yaml
username: ${{ github.actor }}
password: ${{ secrets.GITHUB_TOKEN }}
```
`GITHUB_TOKEN` with `packages: write` can only write to the **repo owner's** package namespace
(`eriklacson`). Pushing to `leansecurity/*` fails with a permission `denied` error at the
`Build and push` step — the package is never created.

### 3. release.md instructions point at a non-existent org
`docs/release.md`:
- Line 23: claims the first run creates `ghcr.io/leansecurity/leansec-nuclei`.
- Line 27 & 167: package page URL `https://github.com/orgs/leansecurity/packages/container/package/nuclei-scanner`
  — this is **doubly stale**: (a) `orgs/leansecurity` does not exist; personal accounts use
  `https://github.com/users/eriklacson/packages/...`, and (b) the path still says `nuclei-scanner`,
  the *pre-rename* package name (should be `leansec-nuclei`).
- Line 35: "add `leansecurity/leansecurity-nuclei` with the Write role" — wrong repo slug; on a
  personal account the package is auto-linked to its source repo anyway.

### 4. Terraform module source URL points at a non-existent repo
`deployments/_example/main.tf:9` and `infra/gcp/README.md:65`:
```
source = "git::https://github.com/leansecurity/leansecurity-nuclei.git//infra/gcp?ref=v1.0.0"
```
`github.com/leansecurity/leansecurity-nuclei` does not exist. Correct repo is
`github.com/eriklacson/leansec-nuclei`. This is a separate "not found" that will bite the moment a
consumer runs `terraform init` — worth fixing in the same pass.

### 5. Secondary check — did the workflow even run?
`publish-image.yaml:7-13` only fires on pushes to `main` (or `v*` tags) **that touch `docker/**` or
`scanner/**`**. The recent merge was the `component/gcp-deploy` work, which was largely
`infra/**`, `docs/**`, `deployments/**`, `.github/**` — all excluded by the path filter. So in
addition to the namespace problem, **the publish job may not have triggered at all** on the merge.
Confirm in the repo's **Actions** tab whether a "Publish Scanner Image" run exists for the merge
commit:
- **No run** → path filter; trigger manually via *Actions → Publish Scanner Image → Run workflow*
  (`workflow_dispatch` is already wired) once the namespace is fixed.
- **Run exists but red** → almost certainly the `denied` push described in finding #2.

---

## Recommended fix (ship under personal repo `eriklacson`)

> Not applied — listed for approval. GHCR namespaces must be **lowercase**; `eriklacson` already is.

### Operative changes (required for the package to exist & be pullable)
| File | Line | Change |
|---|---|---|
| `.github/workflows/publish-image.yaml` | 18 | `IMAGE_NAME: eriklacson/leansec-nuclei` (or `${{ github.repository }}` to auto-track the owner) |
| `infra/gcp/variables.tf` | 16 | default → `ghcr.io/eriklacson/leansec-nuclei:latest` |
| `deployments/_example/terraform.tfvars` | 4 | → `ghcr.io/eriklacson/leansec-nuclei:v1.0.0` |
| `deployments/_example/main.tf` | 9, 44 | module `source` → `github.com/eriklacson/leansec-nuclei.git//infra/gcp?ref=v1.0.0`; default image → `ghcr.io/eriklacson/leansec-nuclei:v1.0.0` |
| `scripts/bootstrap-gcp-client.sh` | 140 | → `ghcr.io/eriklacson/leansec-nuclei:vX.Y.Z` |

### Documentation changes (consistency + the manual one-time steps)
| File | Lines |
|---|---|
| `docs/release.md` | 23, 27, 35, 41, 91, 100, 167, 171, 172 — namespace, **package-page URL to `https://github.com/users/eriklacson/packages/container/package/leansec-nuclei`**, Actions-access repo slug |
| `docs/gcp_architecture.md` | 27, 38, 138, 139, 140 |
| `docs/setup-guide.md` | 76, 264, 352 |
| `infra/gcp/README.md` | 31, 65, 69 |
| `README.md` | 19, 136 |
| `report-gcp-cloud-deploy.md` | 13, 52 (historical; optional) |

### Manual GitHub steps after the code fix (cannot be done from the repo)
1. Merge a change touching `docker/**` or `scanner/**` (or use **Run workflow** / `workflow_dispatch`) so the publish job actually runs.
2. First successful push creates `ghcr.io/eriklacson/leansec-nuclei` as a **private** package.
3. Make it public: `https://github.com/users/eriklacson/packages/container/package/leansec-nuclei`
   → *Package settings → Danger Zone → Change visibility → Public*.
4. Verify anonymously: `docker pull ghcr.io/eriklacson/leansec-nuclei:latest` (no auth prompt).

### Optional / cosmetic (do **not** affect package resolution)
- Local-only build tags `leansecurity/leansec-nuclei:local` and `:test-local`
  (`CLAUDE.md`, `README.md`, `tests/validation/README.md`, `tests/test_container.py:20`) — arbitrary
  local tags, never pushed to GHCR. Rename to `eriklacson/...` only for consistency.
- Project-name prose and the state-bucket suffix `*-tfstate-leansecurity-nuclei`
  (`scripts/bootstrap-gcp-client.sh`, `docs/setup-guide.md`, `deployments/_example/backend.tf`) —
  this is a project name string, not the GHCR namespace; leave or rename per preference.

---

## Migration note (when the `leansecurity` org is created later)
When the org exists and the repo is transferred, the reverse rename applies, plus: the GHCR package
should be transferred/recreated under the org, and consumers' `terraform.tfvars` pins
(`scanner_image`) and the module `source` ref must be bumped. Keeping `IMAGE_NAME` as
`${{ github.repository }}` now would make that transition automatic for the workflow side.
